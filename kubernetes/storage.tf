# The TrueNAS CSI driver, snapshot controller and truenas-nvmeof StorageClass
# are deployed by Argo CD (gitops/apps/truenas-csi.yaml,
# gitops/apps/snapshot-controller.yaml). The API key stays out of Git.
resource "kubernetes_namespace_v1" "truenas_csi" {
  metadata {
    name = "truenas-csi"
  }
}

resource "kubernetes_secret_v1" "truenas_api_credentials" {
  metadata {
    name      = "truenas-api-credentials"
    namespace = kubernetes_namespace_v1.truenas_csi.metadata[0].name
  }

  type = "Opaque"

  data = {
    "api-key" = var.truenas_api_key
  }
}
