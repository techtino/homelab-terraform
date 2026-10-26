resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository = "oci://quay.io/jetstack/charts"
  chart      = "cert-manager"
  version    = "v1.21.2"

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
    })
  ]

  depends_on = [helm_release.cilium]
}

resource "kubernetes_namespace_v1" "step_ca" {
  metadata {
    name = "step-ca"
  }
}

resource "helm_release" "step_ca" {
  name       = "step-certificates"
  namespace  = kubernetes_namespace_v1.step_ca.metadata[0].name
  repository = "https://smallstep.github.io/helm-charts"
  chart      = "step-certificates"
  version    = "1.30.0"
  timeout    = 900

  # The chart's bootstrap Job generates the CA and fills the configmaps read
  # below; it only runs on first install, so wait for it to finish.
  wait_for_jobs = true

  values = [
    yamlencode({
      ca = {
        db = {
          enabled      = true
          persistent   = true
          storageClass = "truenas-nvmeof"
          size         = "1Gi"
        }

        provisioner = {
          name = "admin"
        }
      }
    })
  ]

  depends_on = [
    helm_release.truenas_csi,
    kubernetes_storage_class_v1.truenas_nvmeof,
  ]
}

data "kubernetes_config_map_v1" "step_ca_certs" {
  metadata {
    name      = "step-certificates-certs"
    namespace = kubernetes_namespace_v1.step_ca.metadata[0].name
  }

  depends_on = [helm_release.step_ca]
}

data "kubernetes_config_map_v1" "step_ca_config" {
  metadata {
    name      = "step-certificates-config"
    namespace = kubernetes_namespace_v1.step_ca.metadata[0].name
  }

  depends_on = [helm_release.step_ca]
}

locals {
  step_ca_url = "https://step-certificates.step-ca.svc.cluster.local"
  step_ca_provisioner_kid = jsondecode(
    data.kubernetes_config_map_v1.step_ca_config.data["ca.json"]
  ).authority.provisioners[0].key.kid

}

resource "helm_release" "step_issuer" {
  name       = "step-issuer"
  namespace  = kubernetes_namespace_v1.step_ca.metadata[0].name
  repository = "https://smallstep.github.io/helm-charts"
  chart      = "step-issuer"
  version    = "1.11.0"

  values = [
    yamlencode({
      fullnameOverride = "step-issuer"
    })
  ]

  depends_on = [helm_release.cert_manager]
}

# Managed outside the chart so drift (e.g. a stale kid or caBundle after the CA
# is regenerated) is detected and corrected; Helm only patches changed values.
resource "kubectl_manifest" "step_cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "certmanager.step.sm/v1beta1"
    kind       = "StepClusterIssuer"
    metadata = {
      name = "step-issuer"
    }
    spec = {
      url = local.step_ca_url
      caBundle = base64encode(
        data.kubernetes_config_map_v1.step_ca_certs.data["root_ca.crt"]
      )
      provisioner = {
        name = "admin"
        kid  = local.step_ca_provisioner_kid
        passwordRef = {
          name      = "step-certificates-provisioner-password"
          namespace = kubernetes_namespace_v1.step_ca.metadata[0].name
          key       = "password"
        }
      }
    }
  })

  depends_on = [helm_release.step_issuer]
}
