resource "kubernetes_namespace_v1" "headlamp" {
  metadata {
    name = "headlamp"
  }
}

# Extra permissions on top of the built-in `view` role: read access to cluster
# resources `view` omits (including secrets), plus deleting events. Kept
# separate so they are not granted to every subject bound to `view`.
resource "kubectl_manifest" "headlamp_gateway_readonly" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRole"
    metadata = {
      name = "headlamp-gateway-readonly"
    }
    rules = [
      {
        apiGroups = [""]
        resources = ["nodes"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = [""]
        resources = ["events"]
        verbs     = ["delete"]
      },
      {
        apiGroups = ["gateway.networking.k8s.io"]
        resources = [
          "backendtlspolicies",
          "gatewayclasses",
          "gateways",
          "httproutes",
          "grpcroutes",
          "referencegrants",
          "tcproutes",
          "tlsroutes",
          "udproutes",
          "listenersets",
        ]
        verbs = ["get", "list", "watch"]
      },
      {
        apiGroups = ["cert-manager.io"]
        resources = ["clusterissuers"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["certmanager.step.sm"]
        resources = ["stepissuers", "stepclusterissuers"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["storage.k8s.io"]
        resources = ["storageclasses", "csidrivers", "volumeattachments"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["metallb.io"]
        resources = ["ipaddresspools", "l2advertisements", "bgppeers"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["cilium.io"]
        resources = ["ciliumendpoints", "ciliumnodes", "ciliumnetworkpolicies"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["certificates.k8s.io"]
        resources = ["certificatesigningrequests"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["metrics.k8s.io"]
        resources = ["nodes", "pods"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = [""]
        resources = ["persistentvolumes", "secrets"]
        verbs     = ["get", "list", "watch"]
      },
      {
        apiGroups = ["resource.k8s.io"]
        resources = ["deviceclasses"]
        verbs     = ["get", "list", "watch"]
      },
    ]
  })
}

resource "kubectl_manifest" "headlamp_gateway_readonly_binding" {
  yaml_body = yamlencode({
    apiVersion = "rbac.authorization.k8s.io/v1"
    kind       = "ClusterRoleBinding"
    metadata = {
      name = "headlamp-gateway-readonly"
    }
    subjects = [{
      kind      = "ServiceAccount"
      name      = "headlamp"
      namespace = kubernetes_namespace_v1.headlamp.metadata[0].name
    }]
    roleRef = {
      apiGroup = "rbac.authorization.k8s.io"
      kind     = "ClusterRole"
      name     = "headlamp-gateway-readonly"
    }
  })
}

resource "helm_release" "headlamp" {
  name       = "headlamp"
  namespace  = kubernetes_namespace_v1.headlamp.metadata[0].name
  repository = "https://kubernetes-sigs.github.io/headlamp/"
  chart      = "headlamp"
  version    = "0.46.0"

  values = [
    yamlencode({
      fullnameOverride = "headlamp"

      config = {
        inCluster                    = true
        unsafeUseServiceAccountToken = false
      }

      serviceAccount = {
        create = true
        name   = "headlamp"
      }

      clusterRoleBinding = {
        create          = true
        clusterRoleName = "view"
      }

      service = {
        type = "ClusterIP"
        port = 80
      }

      httpRoute = {
        enabled = false
      }

      ingress = {
        enabled = false
      }
    })
  ]

  depends_on = [
    helm_release.traefik,
    helm_release.metrics_server,
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.headlamp_gateway_readonly,
    kubectl_manifest.headlamp_gateway_readonly_binding,
  ]
}


