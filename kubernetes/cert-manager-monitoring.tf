# Collect cert-manager's controller metrics (port "http-metrics", 9402) and
# alert on certificates that aren't being renewed. The metrics only cover
# Certificates that exist, so a removed app stops alerting straight away.
resource "kubectl_manifest" "cert_manager_service_scrape" {
  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMServiceScrape"
    metadata = {
      name      = "cert-manager"
      namespace = "cert-manager"
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"      = "cert-manager"
          "app.kubernetes.io/component" = "controller"
        }
      }
      endpoints = [{ port = "http-metrics" }]
    }
  })

  depends_on = [
    helm_release.cert_manager,
    helm_release.victoria_metrics_k8s_stack,
  ]
}

resource "kubectl_manifest" "cert_manager_rules" {
  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "cert-manager"
      namespace = "cert-manager"
    }
    spec = {
      groups = [{
        name = "cert-manager"
        rules = [
          {
            # step-ca certificates last 24h and cert-manager renews them 8h
            # before expiry, so under 4h left means renewal has failed.
            alert = "CertificateNotRenewed"
            expr  = "certmanager_certificate_expiration_timestamp_seconds - time() < 4 * 3600"
            for   = "10m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires soon and hasn't been renewed."
              description = "The certificate expires in {{ $value | humanizeDuration }}. Check the Certificate's status and step-ca."
            }
          },
          {
            alert = "CertificateNotRenewed"
            expr  = "certmanager_certificate_expiration_timestamp_seconds - time() < 3600"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires within an hour."
              description = "The certificate expires in {{ $value | humanizeDuration }}. Check the Certificate's status and step-ca."
            }
          },
          {
            # Catches issuing failures (e.g. a new app's first certificate)
            # long before anything is close to expiring.
            alert = "CertificateNotReady"
            expr  = "certmanager_certificate_ready_status{condition=\"True\"} == 0"
            for   = "15m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "Certificate {{ $labels.namespace }}/{{ $labels.name }} isn't ready."
              description = "cert-manager hasn't been able to issue this certificate for 15 minutes. Check `kubectl describe certificate -n {{ $labels.namespace }} {{ $labels.name }}` and step-ca."
            }
          },
        ]
      }]
    }
  })

  depends_on = [helm_release.victoria_metrics_k8s_stack]
}
