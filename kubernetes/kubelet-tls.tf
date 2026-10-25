# kubeadm does not enable kubelet serving-certificate bootstrapping by default.
# Keep the existing kubelet configuration and turn on CSR-based serving certs.
data "kubernetes_config_map_v1" "kubelet_config" {
  metadata {
    name      = "kubelet-config"
    namespace = "kube-system"
  }
}

locals {
  kubelet_config = yamldecode(data.kubernetes_config_map_v1.kubelet_config.data["kubelet"])
}

resource "kubernetes_config_map_v1_data" "kubelet_config" {
  metadata {
    name      = "kubelet-config"
    namespace = "kube-system"
  }

  data = {
    kubelet = yamlencode(merge(local.kubelet_config, {
      serverTLSBootstrap = true
    }))
  }

  # kubeadm originally created this ConfigMap; Terraform now owns this key.
  force = true
}
