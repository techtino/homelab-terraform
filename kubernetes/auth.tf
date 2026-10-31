# Basic auth for routes with auth = true (routes.tf). An HTTPRoute can only
# reference a Middleware in its own namespace, so each namespace with a
# protected route gets its own copy of the Middleware and credentials.
locals {
  basic_auth_namespaces = toset([
    for route in values(local.routed_apps) : route.namespace if route.auth
  ])
}

resource "kubernetes_secret_v1" "basic_auth" {
  for_each = local.basic_auth_namespaces

  metadata {
    name      = "basic-auth"
    namespace = each.key
  }

  data = {
    users = var.basic_auth_htpasswd
  }
}

resource "kubectl_manifest" "basic_auth" {
  for_each = local.basic_auth_namespaces

  yaml_body = yamlencode({
    apiVersion = "traefik.io/v1alpha1"
    kind       = "Middleware"
    metadata = {
      name      = "basic-auth"
      namespace = each.key
    }
    spec = {
      basicAuth = {
        secret = kubernetes_secret_v1.basic_auth[each.key].metadata[0].name
        # Don't pass the Authorization header on to the app; send the
        # logged-in username instead. Any client-supplied X-Remote-User is
        # stripped at the entrypoint first (gateway.tf).
        removeHeader = true
        headerField  = "X-Remote-User"
      }
    }
  })

  depends_on = [helm_release.traefik]
}
