resource "kubernetes_namespace_v1" "homelab_apps" {
  metadata {
    name = "homelab-apps"
  }
}

locals {
  apps = {
    whoami = {
      image    = "traefik/whoami:v1.11.0"
      port     = 80
      replicas = 2
      auth     = true
      env      = { TZ = "Europe/London" }
    }
  }
}

module "apps" {
  for_each = local.apps
  source   = "./modules/app"

  name      = each.key
  namespace = kubernetes_namespace_v1.homelab_apps.metadata[0].name

  image = each.value.image
  port  = each.value.port

  replicas         = try(each.value.replicas, null)
  data_size        = try(each.value.data_size, null)
  data_mount_paths = try(each.value.data_mount_paths, null)
  env              = try(each.value.env, null)

  depends_on = [kubernetes_storage_class_v1.truenas_nvmeof]
}
