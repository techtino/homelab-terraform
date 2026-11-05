# Credentials for routes with auth = true (gitops/charts/homelab/values.yaml).
# The chart's basic-auth Middleware can only read a Secret in its own
# namespace, so each namespace with a protected route gets a copy.
locals {
  basic_auth_namespaces = toset([
    for route in values(local.routed) : route.namespace if route.auth
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
