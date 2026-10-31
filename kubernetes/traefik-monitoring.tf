# Collect Traefik's Prometheus metrics (port "metrics", 9100) and alert on
# failing routes and certificates that aren't being renewed. vmagent picks up
# scrape and rule objects from every namespace.
resource "kubectl_manifest" "traefik_pod_scrape" {
  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMPodScrape"
    metadata = {
      name      = "traefik"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      selector = {
        matchLabels = { "app.kubernetes.io/name" = "traefik" }
      }
      podMetricsEndpoints = [{ port = "metrics" }]
    }
  })

  depends_on = [helm_release.victoria_metrics_k8s_stack]
}

locals {
  # Traefik names Gateway API services like
  # httproute-<ns>-<name>-gw-...-svc-<ns>-<name>-<n>@kubernetesgateway.
  # Pull out "<ns>-<name>" as a readable route label.
  traefik_route_label = "\"route\", \"$1\", \"service\", \".*-svc-(.+)-[0-9]+@kubernetesgateway\""
}

resource "kubectl_manifest" "traefik_rules" {
  yaml_body = yamlencode({
    apiVersion = "operator.victoriametrics.com/v1beta1"
    kind       = "VMRule"
    metadata = {
      name      = "traefik"
      namespace = kubernetes_namespace_v1.traefik.metadata[0].name
    }
    spec = {
      groups = [{
        name = "traefik"
        rules = [
          {
            # Needs some traffic (over ~6 requests per 5m) so one failed
            # request on an idle route doesn't page.
            alert = "TraefikRouteErrorRateHigh"
            expr  = <<-EOT
              label_replace(
                (
                  sum by (service) (rate(traefik_service_requests_total{code=~"5.."}[5m]))
                    / sum by (service) (rate(traefik_service_requests_total[5m]))
                ) > 0.1
                and sum by (service) (rate(traefik_service_requests_total[5m])) > 0.02,
                ${local.traefik_route_label}
              )
            EOT
            for   = "10m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "{{ $labels.route }} is returning 5xx errors."
              description = "{{ $value | humanizePercentage }} of requests to {{ $labels.route }} through Traefik returned a 5xx status over the last 5 minutes."
            }
          },
          {
            # step-ca certificates last 24h and cert-manager renews them 8h
            # before expiry, so under 4h left means renewal has failed.
            alert = "TraefikCertificateNotRenewed"
            expr  = "(max by (cn) (traefik_tls_certs_not_after) - time()) < 4 * 3600"
            for   = "10m"
            labels = {
              severity = "warning"
            }
            annotations = {
              summary     = "Certificate for {{ $labels.cn }} expires soon and hasn't been renewed."
              description = "The certificate Traefik serves for {{ $labels.cn }} expires in {{ $value | humanizeDuration }}. Check the cert-manager Certificate and step-ca."
            }
          },
          {
            alert = "TraefikCertificateNotRenewed"
            expr  = "(max by (cn) (traefik_tls_certs_not_after) - time()) < 3600"
            labels = {
              severity = "critical"
            }
            annotations = {
              summary     = "Certificate for {{ $labels.cn }} expires within an hour."
              description = "The certificate Traefik serves for {{ $labels.cn }} expires in {{ $value | humanizeDuration }}. Check the cert-manager Certificate and step-ca."
            }
          },
        ]
      }]
    }
  })

  depends_on = [helm_release.victoria_metrics_k8s_stack]
}
