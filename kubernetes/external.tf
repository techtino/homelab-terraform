locals {
  # Services outside the cluster, routed through the gateway's websecure listener.
  external_services = {
    proxmox = { ip = "192.168.1.31", port = 8006 }
    router  = { ip = "192.168.1.1", port = 443 }
    truenas = { ip = "192.168.1.118", port = 443 }
  }
}

resource "kubernetes_service_v1" "external_services" {
  for_each = local.external_services

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
  }

  spec {
    # Port name "https" makes Traefik use TLS to the backend.
    port {
      name        = "https"
      port        = each.value.port
      target_port = each.value.port
    }
  }
}

resource "kubernetes_endpoint_slice_v1" "external_services" {
  for_each = local.external_services

  metadata {
    name      = each.key
    namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    labels = {
      "kubernetes.io/service-name" = kubernetes_service_v1.external_services[each.key].metadata[0].name
    }
  }

  address_type = "IPv4"

  endpoint {
    addresses = [each.value.ip]

    # Traefik skips endpoints that aren't explicitly ready.
    condition {
      ready = true
    }
  }

  port {
    name         = "https"
    port         = each.value.port
    app_protocol = "https"
  }
}
