resource "kubernetes_secret_v1" "this_env" {
  count = length(var.env) > 0 ? 1 : 0

  metadata {
    name      = "${var.name}-env"
    namespace = var.namespace
  }

  type = "Opaque"

  data = var.env
}

locals {
  persistent = var.data_size != null
}

# Persistent application data
resource "kubernetes_persistent_volume_claim_v1" "this_data" {
  count = local.persistent ? 1 : 0

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
resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    replicas = var.replicas

    # A ReadWriteOnce volume can only be mounted by one pod at a time.
    strategy {
      type = local.persistent ? "Recreate" : "RollingUpdate"
    }

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
        # Prefer one replica per node, but still schedule if a node is down.
        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"

          label_selector {
            match_labels = {
              app = var.name
            }
          }
        }

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

          # Only send traffic to pods that are accepting connections.
          readiness_probe {
            tcp_socket {
              port = var.port
            }
            period_seconds = 2
          }

          dynamic "volume_mount" {
            for_each = local.persistent ? toset(var.data_mount_paths) : []

            content {
              name       = "app-data"
              mount_path = volume_mount.value
            }
          }
        }

        dynamic "volume" {
          for_each = local.persistent ? [1] : []

          content {
            name = "app-data"

            persistent_volume_claim {
              claim_name = kubernetes_persistent_volume_claim_v1.this_data[0].metadata[0].name
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = !(local.persistent && var.replicas > 1)
      error_message = "Apps with persistent data (data_size) can only run one replica."
    }
  }
}

# Keep at least one replica running through node drains.
resource "kubernetes_pod_disruption_budget_v1" "this" {
  count = var.replicas > 1 ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
  }

  spec {
    min_available = 1

    selector {
      match_labels = {
        app = var.name
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

