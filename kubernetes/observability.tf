resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

locals {
  victoria_metrics_url = "http://vmsingle-victoria-metrics-single-server.observability.svc:8428"
  victoria_logs_url    = "http://vlogs-victoria-logs-single-server.observability.svc:9428"

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

resource "helm_release" "victoria_logs" {
  name       = "vlogs"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-logs-single"
  version    = "0.13.9"
  timeout    = 900

  values = [
    yamlencode({
      server = {
        retentionPeriod = "7d"
        resources       = local.observability_resources.vlogs
        persistentVolume = {
          enabled          = true
          size             = "100Gi"
          storageClassName = "truenas-nvmeof"
        }
      }
    })
  ]

  depends_on = [
    helm_release.truenas_csi,
    kubernetes_storage_class_v1.truenas_nvmeof,
  ]
}

resource "helm_release" "victoria_logs_collector" {
  name       = "vlagent"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-logs-collector"
  version    = "0.2.4"
  timeout    = 900

  values = [
    yamlencode({
      tolerations = [{
        key      = "node-role.kubernetes.io/control-plane"
        operator = "Exists"
        effect   = "NoSchedule"
      }]

      remoteWrite = [{
        url = local.victoria_logs_url
      }]

      resources = local.observability_resources.collector
    })
  ]

  depends_on = [helm_release.victoria_logs]
}

resource "helm_release" "victoria_metrics" {
  name       = "vmsingle"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-single"
  version    = "0.49.0"
  timeout    = 900

  values = [
    yamlencode({
      server = {
        retentionPeriod = "1" # months
        resources       = local.observability_resources.vmsingle
        persistentVolume = {
          enabled          = true
          size             = "100Gi"
          storageClassName = "truenas-nvmeof"
        }
      }
    })
  ]

  depends_on = [
    helm_release.truenas_csi,
    kubernetes_storage_class_v1.truenas_nvmeof,
  ]
}

# Cluster metrics collection and the upstream Kubernetes dashboards. Keep the
# existing Grafana and VictoriaMetrics Single releases as the serving UI and
# long-term store.
resource "helm_release" "victoria_metrics_k8s_stack" {
  name       = "vm-k8s-stack"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://victoriametrics.github.io/helm-charts/"
  chart      = "victoria-metrics-k8s-stack"
  version    = "0.96.0"
  timeout    = 900

  values = [
    yamlencode({
      grafana = {
        enabled = false
      }

      vmsingle = {
        enabled = false
      }

      vmcluster = {
        enabled = false
      }

      # Evaluates the chart's default alert rules against VictoriaMetrics Single.
      # Alert state is written back so it survives vmalert restarts.
      vmalert = {
        enabled = true
        name    = "vmalert"
        spec = {
          datasource  = { url = local.victoria_metrics_url }
          remoteRead  = { url = local.victoria_metrics_url }
          remoteWrite = { url = "${local.victoria_metrics_url}/api/v1/write" }
          resources   = local.observability_resources.vmalert
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
          remoteWrite = [{
            url = "${local.victoria_metrics_url}/api/v1/write"
          }]
          resources = local.observability_resources.vmagent
        }
      }

      defaultDashboards = {
        enabled = true
        labels = {
          grafana_dashboard = "1"
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
    })
  ]

  depends_on = [
    helm_release.victoria_metrics,
    helm_release.grafana,
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

resource "helm_release" "grafana" {
  name       = "grafana"
  namespace  = kubernetes_namespace_v1.observability.metadata[0].name
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "grafana"
  version    = "13.5.0"
  timeout    = 900

  values = [
    yamlencode({
      fullnameOverride = "grafana"

      service = {
        type = "ClusterIP"
        port = 80
      }

      ingress = {
        enabled = false
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
          enabled         = true
          label           = "grafana_dashboard"
          labelValue      = "1"
          searchNamespace = "observability"
        }
      }

      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name      = "VictoriaMetrics"
              type      = "victoriametrics-metrics-datasource"
              access    = "proxy"
              url       = local.victoria_metrics_url
              isDefault = true
            },
            {
              name   = "Prometheus"
              type   = "prometheus"
              access = "proxy"
              url    = local.victoria_metrics_url
              uid    = "prometheus"
            },
            {
              name   = "VictoriaLogs"
              type   = "victoriametrics-logs-datasource"
              access = "proxy"
              url    = local.victoria_logs_url
            },
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.victoria_logs,
    helm_release.victoria_metrics,
  ]
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
