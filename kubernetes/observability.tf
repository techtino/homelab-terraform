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

      vmalert = {
        enabled = false
      }

      # Nothing sends alerts without vmalert, and its generated StatefulSet name
      # pushes the pod's controller-revision-hash label past 63 characters.
      alertmanager = {
        enabled = false
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
