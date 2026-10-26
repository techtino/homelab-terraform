locals {
  routed_apps = merge(
    {
      for name, app in local.apps_by_name : name => merge(app, {
        namespace = kubernetes_namespace_v1.homelab_apps.metadata[0].name
      })
    },
    {
      headlamp = {
        namespace       = "headlamp"
        domains         = ["headlamp.home.arpa"]
        tls_secret_name = "headlamp-tls"
        port            = 80
      }
      grafana = {
        namespace       = "observability"
        domains         = ["grafana.home.arpa"]
        tls_secret_name = "grafana-tls"
        port            = 80
      }
    },
    {
      for name, svc in local.external_services : name => {
        namespace       = kubernetes_namespace_v1.traefik.metadata[0].name
        domains         = ["${name}.home.arpa"]
        tls_secret_name = "${name}-tls"
        port            = svc.port
      }
    }
  )
}

resource "kubectl_manifest" "http_routes" {
  for_each = local.routed_apps

  yaml_body = yamlencode({
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.key
      namespace = each.value.namespace
    }
    spec = {
      parentRefs = [{
        name        = "traefik-gateway"
        namespace   = "traefik"
        sectionName = "websecure"
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
    kubernetes_endpoint_slice_v1.external_services,
  ]
}
