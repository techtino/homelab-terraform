# Namespace and CurseForge API key for the All the Mods 10 server deployed by
# Argo CD (gitops/apps/minecraft.yaml). The server uses the key to download
# the modpack, and it's created here so it stays out of Git.
resource "kubernetes_namespace_v1" "minecraft" {
  metadata {
    name = "minecraft"
  }
}

resource "kubernetes_secret_v1" "curseforge" {
  metadata {
    name      = "curseforge"
    namespace = kubernetes_namespace_v1.minecraft.metadata[0].name
  }

  data = {
    api-key = var.curseforge_api_key
  }
}

# Minecraft has its own LoadBalancer IP (gitops/manifests/minecraft/atm10.yaml)
# rather than going through Traefik, so it gets its own DNS record.
resource "opnsense_unbound_host_override" "minecraft" {
  enabled     = true
  hostname    = "minecraft"
  domain      = local.domain
  server      = "192.168.1.242"
  description = "Managed by OpenTofu: minecraft.${local.domain}"
}
