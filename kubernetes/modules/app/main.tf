locals {
  extra_volume_entries = [
    for i, host_path in sort(keys(var.extra_volumes)) : {
      name       = "hostpath-${i}"
      host_path  = host_path
      mount_path = var.extra_volumes[host_path]
    }
  ]
}

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
    replicas     = var.replica_count

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

          dynamic "env" {
            for_each = var.env

            content {
              name  = env.key
              value = env.value
            }
          }

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

          dynamic "port" {
            for_each = var.extra_ports

            content {
              name           = port.value.name
              container_port = port.value.container_port
              protocol       = port.value.protocol
            }
          }

          dynamic "volume_mount" {
            for_each = toset(var.data_mount_paths)

            content {
              name       = "app-data"
              mount_path = volume_mount.value
            }
          }

          dynamic "volume_mount" {
            for_each = local.extra_volume_entries

            content {
              name       = volume_mount.value.name
              mount_path = volume_mount.value.mount_path
            }
          }
        }

        volume {
          name = "app-data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.this_data.metadata[0].name
          }
        }

        dynamic "volume" {
          for_each = local.extra_volume_entries

          content {
            name = volume.value.name

            host_path {
              path = volume.value.host_path
              type = "Directory"
            }
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

    dynamic "port" {
      for_each = var.extra_ports

      content {
        name        = port.value.name
        port        = port.value.container_port
        target_port = port.value.container_port
        protocol    = port.value.protocol
      }
    }
  }
}

