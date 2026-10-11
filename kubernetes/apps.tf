
resource "kubernetes_deployment_v1" "hello" {
  metadata {
    name      = "hello"
    namespace = "default"
    labels = {
      app = "hello"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "hello"
      }
    }

    template {
      metadata {
        labels = {
          app = "hello"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"

          port {
            container_port = 80
          }
        }
      }
    }
  }

  depends_on = [helm_release.cilium]
}

resource "kubernetes_service_v1" "hello" {
  metadata {
    name      = "hello"
    namespace = "default"
  }

  spec {
    selector = {
      app = "hello"
    }

    port {
      port        = 80
      target_port = "80"
    }
  }

  depends_on = [helm_release.cilium]
}

resource "kubernetes_ingress_v1" "hello" {
  metadata {
    name      = "hello"
    namespace = "default"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "hello.home.arpa"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.hello.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.cilium]
}


resource "kubernetes_namespace_v1" "portainer" {
  metadata {
    name = "portainer"
  }
}

resource "kubernetes_persistent_volume_claim_v1" "portainer_data" {
  metadata {
    name      = "portainer-data"
    namespace = kubernetes_namespace_v1.portainer.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "truenas-nvmeof"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }

  depends_on = [
    helm_release.truenas_csi,
  ]
}

resource "helm_release" "portainer" {
  name       = "portainer"
  namespace  = kubernetes_namespace_v1.portainer.metadata[0].name
  repository = "https://portainer.github.io/k8s/"
  chart      = "portainer"
  version    = "2.39.0"

  values = [
    yamlencode({
      replicaCount = 1

      service = {
        type = "ClusterIP"
      }

      persistence = {
        enabled       = true
        existingClaim = "portainer-data"
      }

      ingress = {
        enabled          = true
        ingressClassName = "traefik"

        hosts = [
          {
            host = "portainer.home.arpa"

            paths = [
              {
                path = "/"
                port = 9000
              }
            ]
          }
        ]
      }

      trusted_origins = {
        enabled = true
        domains = "portainer.home.arpa"
      }
    })
  ]

  depends_on = [
    kubernetes_persistent_volume_claim_v1.portainer_data,
    helm_release.cilium,
  ]
}
