locals {
  domain = "home.arpa"

  # Everything served through the gateway, as name => { namespace, port, auth }.
  # Each entry gets an HTTPRoute, certificate and DNS record for
  # <name>.home.arpa, with its TLS secret named <name>-tls. auth = true puts the
  # route behind basic auth (auth.tf).
  #
  # Module-managed apps (apps.tf) and external services (external.tf) are added
  # automatically; list any other in-cluster Service here.
  routed_apps = merge(
    {
      for name, app in local.apps : name => {
        namespace = kubernetes_namespace_v1.homelab_apps.metadata[0].name
        port      = app.port
        auth      = try(app.auth, false)
      }
    },
    {
      for name, svc in local.external_services : name => {
        namespace = kubernetes_namespace_v1.traefik.metadata[0].name
        port      = svc.port
        auth      = false # these have their own login
      }
    },
    {
      headlamp = { namespace = kubernetes_namespace_v1.headlamp.metadata[0].name, port = 80, auth = true }
      grafana  = { namespace = kubernetes_namespace_v1.observability.metadata[0].name, port = 80, auth = false }
    },
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
      hostnames = ["${each.key}.${local.domain}"]
      rules = [merge(
        {
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
        },
        each.value.auth ? {
          filters = [{
            type = "ExtensionRef"
            extensionRef = {
              group = "traefik.io"
              kind  = "Middleware"
              name  = "basic-auth"
            }
          }]
        } : {},
      )]
    }
  })

  depends_on = [
    helm_release.traefik,
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.basic_auth,
  ]
}
