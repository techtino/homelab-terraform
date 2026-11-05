# Apps and routes are deployed by Argo CD from gitops/charts/homelab. OpenTofu
# reads the same values file for the two things Argo CD can't do from Git: DNS
# records on OPNsense (dns.tf) and basic auth credentials (auth.tf).
locals {
  homelab = yamldecode(file("${path.module}/../gitops/charts/homelab/values.yaml"))
  domain  = local.homelab.domain

  # Traefik's LoadBalancer IP (gitops/apps/traefik.yaml).
  gateway_ip = "192.168.1.241"

  # Every name served through the gateway, as name => { namespace, auth }.
  routed = merge(
    {
      for name, app in local.homelab.apps : name => {
        namespace = kubernetes_namespace_v1.homelab_apps.metadata[0].name
        auth      = try(app.auth, false)
      }
    },
    {
      for name, route in local.homelab.routes : name => {
        namespace = route.namespace
        auth      = try(route.auth, false)
      }
    },
    {
      for name, _ in local.homelab.external : name => {
        namespace = "traefik"
        auth      = false
      }
    },
  )
}

# Created here so the basic auth credentials can be stored in it before Argo
# CD deploys the apps.
resource "kubernetes_namespace_v1" "homelab_apps" {
  metadata {
    name = "homelab-apps"
  }
}
