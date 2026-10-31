resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

locals {
  victoria_metrics_url = "http://vmsingle-victoria-metrics-single-server.observability.svc:8428"
  victoria_logs_url    = "http://vlogs-victoria-logs-single-server.observability.svc:9428"
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
        }
      }

      # A short name keeps the operator's StatefulSet name, and with it the
      # pod's controller-revision-hash label, under 63 characters.
      alertmanager = {
        enabled = true
        name    = "alertmanager"
        spec = {
          configSecret = kubernetes_secret_v1.alertmanager_config.metadata[0].name
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
            # Watchdog always fires to prove the pipeline works, and
            # InfoInhibitor only exists to mute info alerts.
            matchers = ["alertname=~\"Watchdog|InfoInhibitor\""]
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

      receivers = [
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
      ]
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

      sidecar = {
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
