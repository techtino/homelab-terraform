resource "kubectl_manifest" "http_routes" {
  for_each = local.apps_by_name

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.key
      namespace = try(each.value.module_managed, true) ? kubernetes_namespace_v1.homelab_apps.metadata[0].name : each.value.namespace
    }
    spec = {
      parentRefs = [{
        name      = "traefik-gateway"
        namespace = "traefik"
      }]
      hostnames = sort(tolist(each.value.domains))
      rules = [{
        matches = [{
          path = {
            type  = "PathPrefix"
            value = "/"
          }
        }]
        backendRefs = [{
          name = each.key
          port = each.value.port
        }]
      }]
    }
  })

  depends_on = [
    helm_release.traefik,
    helm_release.headlamp,
    helm_release.grafana,
    kubectl_manifest.gateway_api_crds,
  ]
}
