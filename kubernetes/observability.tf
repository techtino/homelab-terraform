resource "kubernetes_namespace_v1" "observability" {
  metadata {
    name = "observability"
  }
}

# The metrics, logs and alerting stack is deployed by Argo CD
# (gitops/apps/observability.yaml). The Secrets it uses are created here so
# their contents stay out of Git.

# Grafana's admin login. Grafana only reads it when it first creates its
# database, so changing it later needs `grafana cli admin reset-admin-password`.
resource "random_password" "grafana_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.observability.metadata[0].name
  }

  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana_admin.result
  }
}

# Alertmanager config, kept out of the Argo CD values so the Pushover
# credentials aren't stored in Git.
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
        equal           = ["alertname", "namespace", "name", "route"]
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
