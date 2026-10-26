resource "kubernetes_secret_v1" "this_env" {
  count = length(var.env) > 0 ? 1 : 0

  metadata {
    name      = "${var.name}-env"
    namespace = var.namespace
  }

  type = "Opaque"

  data = var.env
}

# Persistent application data
resource "kubernetes_persistent_volume_claim_v1" "this_data" {
  metadata {
    name      = "${var.name}-data"
    namespace = var.namespace
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "truenas-nvmeof"

    resources {
      requests = {
        storage = var.data_size
      }
    }
  }
}

# Application workload
resource "kubernetes_stateful_set_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    service_name = var.name
    replicas     = 1

    selector {
      match_labels = {
        app = var.name
      }
    }

    template {
      metadata {
        labels = {
          app = var.name
        }
      }

      spec {
        container {
          name  = var.name
          image = var.image

          dynamic "env_from" {
            for_each = length(var.env) > 0 ? [1] : []

            content {
              secret_ref {
                name = kubernetes_secret_v1.this_env[0].metadata[0].name
              }
            }
          }

          port {
            name           = "http"
            container_port = var.port
            protocol       = "TCP"
          }

          dynamic "volume_mount" {
            for_each = toset(var.data_mount_paths)

            content {
              name       = "app-data"
              mount_path = volume_mount.value
            }
          }
        }

        volume {
          name = "app-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.this_data.metadata[0].name
          }
        }
      }
    }
  }
}

# Internal ClusterIP Service
resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace

    labels = {
      app = var.name
    }
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = var.name
    }

    port {
      name        = "http"
      port        = var.port
      target_port = var.port
      protocol    = "TCP"
    }
  }
}

