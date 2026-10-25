resource "kubernetes_namespace_v1" "homelab_apps" {
  metadata {
    name = "homelab-apps"
  }
}

locals {
  apps = [
    {
      name             = "whoami"
      image            = "traefik/whoami:v1.11.0"
      data_size        = "1Gi"
      data_mount_paths = ["/app-data"]
      env              = { TZ = "Europe/London" }
    },
    {
      name             = "test"
      image            = "ghcr.io/kljensen/hello-world-http:latest"
      port             = 8000
      data_size        = "1Gi"
      data_mount_paths = ["/app-data"]
      env = {
        TZ   = "Europe/London"
        HOST = "0.0.0.0"
        PORT = "8000"
      }
    },
  ]

  apps_by_name = {
    for app in local.apps : app.name => merge(app, {
      domains         = concat(try(app.domains, ["${app.name}.home.arpa"]), try(app.additional_domains, []))
      tls_secret_name = try(app.tls_secret_name, "${app.name}-tls")
      port            = try(app.port, 80)
    })
  }
}

module "apps" {
  for_each = local.apps_by_name
  source   = "./modules/app"

  name      = each.value.name
  namespace = kubernetes_namespace_v1.homelab_apps.metadata[0].name

  image = each.value.image
  port  = each.value.port

  data_size        = try(each.value.data_size, null)
  data_mount_paths = try(each.value.data_mount_paths, null)
  extra_volumes    = try(each.value.extra_volumes, null)
  extra_ports      = try(each.value.extra_ports, null)
  env              = try(each.value.env, null)

  depends_on = [kubernetes_storage_class_v1.truenas_nvmeof]
}
