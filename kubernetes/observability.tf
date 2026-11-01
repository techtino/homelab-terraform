resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

locals {
  # Requests are close to observed usage so the scheduler can place pods by
  # real load. Memory limits stop a leak from exhausting a node. No CPU limits,
  # which would only cause throttling.
  observability_resources = {
    for name, r in {
      grafana            = { cpu = "50m", memory = "768Mi", limit = "1536Mi" }
      grafana_sidecar    = { cpu = "10m", memory = "128Mi", limit = "256Mi" }
      vmsingle           = { cpu = "100m", memory = "512Mi", limit = "2Gi" }
      vlogs              = { cpu = "50m", memory = "256Mi", limit = "1Gi" }
      collector          = { cpu = "20m", memory = "64Mi", limit = "256Mi" }
      vmagent            = { cpu = "50m", memory = "128Mi", limit = "512Mi" }
      vmalert            = { cpu = "50m", memory = "96Mi", limit = "512Mi" }
      vmauth             = { cpu = "10m", memory = "32Mi", limit = "128Mi" }
      alertmanager       = { cpu = "20m", memory = "64Mi", limit = "256Mi" }
      operator           = { cpu = "20m", memory = "96Mi", limit = "256Mi" }
      kube_state_metrics = { cpu = "20m", memory = "96Mi", limit = "256Mi" }
      node_exporter      = { cpu = "20m", memory = "64Mi", limit = "128Mi" }
      } : name => {
      requests = { cpu = r.cpu, memory = r.memory }
      limits   = { memory = r.limit }
    }
  }
}

# The whole metrics, logs and alerting stack: VictoriaMetrics and VictoriaLogs
# storage, collectors, vmalert, Alertmanager and Grafana. The chart wires the
# components (remote write, alert datasources, Grafana datasources) to each
# other.
resource "helm_release" "victoria_metrics_k8s_stack" {
  name       = "vm-k8s-stack"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-k8s-stack"
  version    = "0.96.0"
  timeout    = 900

  values = [
    yamlencode({
      vmsingle = {
        enabled = true
        name    = "vmsingle"
        spec = {
          retentionPeriod = "1" # months
          resources       = local.observability_resources.vmsingle
          storage = {
            storageClassName = "truenas-nvmeof"
            resources        = { requests = { storage = "100Gi" } }
          }
        }
      }

      vlsingle = {
        enabled = true
        name    = "vlogs"
        spec = {
          retentionPeriod = "7d"
          resources       = local.observability_resources.vlogs
          storage = {
            storageClassName = "truenas-nvmeof"
            resources        = { requests = { storage = "100Gi" } }
          }
        }
      }

      # Runs on every node, including control planes, and ships all container
      # logs to VictoriaLogs.
      vlagent = {
        enabled = true
        name    = "vlagent"
        spec = {
          k8sCollector = { enabled = true }
          resources    = local.observability_resources.collector
          tolerations = [{
            key      = "node-role.kubernetes.io/control-plane"
            operator = "Exists"
            effect   = "NoSchedule"
          }]
        }
      }

      # Evaluates the chart's default alert rules. Alert state is written back
      # to VictoriaMetrics so it survives vmalert restarts.
      vmalert = {
        enabled = true
        name    = "vmalert"
        spec = {
          resources = local.observability_resources.vmalert
        }
      }

      # A short name keeps the operator's StatefulSet name, and with it the
      # pod's controller-revision-hash label, under 63 characters.
      alertmanager = {
        enabled = true
        name    = "alertmanager"
        spec = {
          configSecret = kubernetes_secret_v1.alertmanager_config.metadata[0].name
          resources    = local.observability_resources.alertmanager
        }
      }

      kubeEtcd = {
        enabled = true
        service = {
          port       = 2381
          targetPort = 2381
        }
        vmScrape = {
          spec = {
            endpoints = [{
              port            = "http-metrics"
              scheme          = "http"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tlsConfig       = null
            }]
          }
        }
      }

      kubeControllerManager = {
        enabled = true
        vmScrape = {
          spec = {
            endpoints = [{
              port            = "http-metrics"
              scheme          = "https"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tlsConfig = {
                insecureSkipVerify = true
              }
            }]
          }
        }
      }

      kubeScheduler = {
        enabled = true
        vmScrape = {
          spec = {
            endpoints = [{
              port            = "http-metrics"
              scheme          = "https"
              bearerTokenFile = "/var/run/secrets/kubernetes.io/serviceaccount/token"
              tlsConfig = {
                insecureSkipVerify = true
              }
            }]
          }
        }
      }

      vmagent = {
        enabled = true
        spec = {
          resources = local.observability_resources.vmagent
        }
      }

      defaultDashboards = {
        enabled = true
        labels = {
          grafana_dashboard = "1"
        }
      }

      # With both VictoriaMetrics and VictoriaLogs enabled, the chart puts a
      # vmauth in front of them as vmalert's datasource, routing LogsQL queries
      # to VictoriaLogs so rules can alert on logs too.
      internal = {
        vmauth = {
          spec = {
            resources = local.observability_resources.vmauth
          }
        }
      }

      "victoria-metrics-operator" = {
        operator = {
          disable_prometheus_converter = true
        }
        resources = local.observability_resources.operator
      }

      "kube-state-metrics" = {
        resources = local.observability_resources.kube_state_metrics
      }

      "prometheus-node-exporter" = {
        resources = local.observability_resources.node_exporter
      }

      # Datasources for VictoriaMetrics, VictoriaLogs and Alertmanager are
      # provisioned by the chart. The plugin datasources are only added when
      # their plugin is listed here.
      grafana = {
        enabled = true

        # Matches the Service name routes.tf points the grafana route at.
        fullnameOverride = "grafana"

        service = {
          type = "ClusterIP"
          port = 80
        }

        persistence = {
          enabled          = true
          type             = "pvc"
          storageClassName = "truenas-nvmeof"
          size             = "5Gi"
        }

        plugins = [
          "victoriametrics-metrics-datasource",
          "victoriametrics-logs-datasource",
        ]

        resources = local.observability_resources.grafana

        # The ReadWriteOnce PVC can only attach to one node, so stop the old pod
        # before starting the new one instead of rolling.
        deploymentStrategy = {
          type = "Recreate"
        }

        sidecar = {
          resources = local.observability_resources.grafana_sidecar
          dashboards = {
            searchNamespace = kubernetes_namespace_v1.observability.metadata[0].name
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.truenas_csi,
    kubernetes_storage_class_v1.truenas_nvmeof,
  ]
}

# Alertmanager config, kept out of the Helm values so the Pushover credentials
# aren't stored in the Helm release.
resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }

  data = {
    "alertmanager.yaml" = yamlencode({
      route = {
        receiver        = "pushover"
        group_by        = ["alertname", "namespace"]
        group_wait      = "30s"
        group_interval  = "5m"
        repeat_interval = "12h"
        routes = [
          {
            # Watchdog always fires. Pinging the dead man's switch with it
            # every minute means healthchecks.io alerts if the pings stop,
            # i.e. if vmalert, Alertmanager or the cluster is down.
            matchers        = ["alertname=\"Watchdog\""]
            receiver        = var.healthchecks_ping_url != "" ? "deadmans-switch" : "blackhole"
            group_wait      = "0s"
            group_interval  = "1m"
            repeat_interval = "1m"
          },
          {
            # InfoInhibitor only exists to mute info alerts.
            matchers = ["alertname=\"InfoInhibitor\""]
            receiver = "blackhole"
          },
          {
            matchers = ["severity=\"info\""]
            receiver = "blackhole"
          },
          {
            matchers = ["severity=\"critical\""]
            receiver = "pushover-critical"
          },
        ]
      }

      inhibit_rules = [{
        # Don't send a warning when the same problem is already critical.
        source_matchers = ["severity=\"critical\""]
        target_matchers = ["severity=\"warning\""]
        equal           = ["alertname", "namespace", "cn", "route"]
      }]

      receivers = concat([
        { name = "blackhole" },
        {
          name = "pushover"
          pushover_configs = [{
            user_key      = var.pushover_user_key
            token         = var.pushover_api_token
            priority      = "0"
            send_resolved = true
          }]
        },
        {
          name = "pushover-critical"
          pushover_configs = [{
            user_key      = var.pushover_user_key
            token         = var.pushover_api_token
            priority      = "{{ if eq .Status \"firing\" }}1{{ else }}0{{ end }}"
            send_resolved = true
          }]
        },
        ], var.healthchecks_ping_url != "" ? [{
          name = "deadmans-switch"
          webhook_configs = [{
            url           = var.healthchecks_ping_url
            send_resolved = false
          }]
      }] : [])
    })
  }
}

# Dashboards in dashboards/ are loaded by Grafana's sidecar, which watches for
# ConfigMaps with the grafana_dashboard label.
resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name      = "homelab-dashboards"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    for f in fileset("${path.module}/dashboards", "*.json") : f => file("${path.module}/dashboards/${f}")
  }
}
