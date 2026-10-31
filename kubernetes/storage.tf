resource "helm_release" "truenas_csi" {
  name            = "truenas-csi"
  namespace       = kubernetes_namespace_v1.truenas_csi.metadata[0].name
  repository      = "https://raw.githubusercontent.com/truenas/truenas-csi/master/charts"
  chart           = "truenas-csi"
  version         = "1.4.0"
  upgrade_install = true
  wait            = true
  atomic          = true
  timeout         = 900

  values = [
    yamlencode({
      truenas = {
        url               = "wss://192.168.1.118"
        defaultPool       = "FastNAS"
        nvmeofPortal      = "192.168.1.118:4420"
        insecureSkipTLS   = true
        existingSecret    = "truenas-api-credentials"
        existingSecretKey = "api-key"
      }

      # Deleting a VolumeSnapshot also deletes the ZFS snapshot on TrueNAS.
      volumeSnapshotClass = {
        enabled        = true
        deletionPolicy = "Delete"
        annotations = {
          "snapshot.storage.kubernetes.io/is-default-class" = "true"
        }
      }
    })
  ]

  depends_on = [
    kubernetes_secret_v1.truenas_api_credentials,
    helm_release.cilium,
    helm_release.snapshot_controller,
  ]
}

# VolumeSnapshot CRDs and the controller that handles them. The TrueNAS CSI
# driver's csi-snapshotter sidecar needs both for PVC snapshots.
resource "helm_release" "snapshot_controller" {
  name       = "snapshot-controller"
  namespace  = "kube-system"
  repository = "https://piraeus.io/helm-charts/"
  chart      = "snapshot-controller"
  version    = "5.4.0"
  timeout    = 900

  depends_on = [helm_release.cilium]
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

resource "kubernetes_namespace_v1" "truenas_csi" {
  metadata {
    name = "truenas-csi"
  }
}

resource "kubernetes_storage_class_v1" "truenas_nvmeof" {
  metadata {
    name = "truenas-nvmeof"
  }

  storage_provisioner    = "csi.truenas.io"
  reclaim_policy         = "Retain"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    protocol    = "nvmeof"
    pool        = "FastNAS"
    datasetPath = "kubernetes/volumes"
    sparse      = "true"
  }

  depends_on = [
    helm_release.truenas_csi,
  ]
}