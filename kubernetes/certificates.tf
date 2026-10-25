resource "kubectl_manifest" "certificates" {
  for_each = local.routed_apps

  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = each.key
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      secretName  = each.value.tls_secret_name
      dnsNames    = sort(tolist(each.value.domains))
      duration    = "24h"
      renewBefore = "8h"
      issuerRef = {
        name  = "step-issuer"
        kind  = "StepClusterIssuer"
        group = "certmanager.step.sm"
      }
    }
  })

  depends_on = [helm_release.step_issuer]
}
