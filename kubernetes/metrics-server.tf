resource "helm_release" "metrics_server" {
  name            = "metrics-server"
  namespace       = "kube-system"
  repository      = "https://kubernetes-sigs.github.io/metrics-server/"
  chart           = "metrics-server"
  version         = "3.14.0"
  upgrade_install = true
  wait            = false

  values = [
    yamlencode({
      defaultArgs = [
        "--cert-dir=/tmp",
        "--kubelet-certificate-authority=/etc/metrics-server/kubelet-ca/ca.crt",
        "--kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname",
        "--kubelet-use-node-status-port",
        "--metric-resolution=15s",
      ]

      extraVolumes = [{
        name = "kubelet-ca"
        configMap = {
          name = "kube-root-ca.crt"
        }
      }]

      extraVolumeMounts = [{
        name      = "kubelet-ca"
        mountPath = "/etc/metrics-server/kubelet-ca"
        readOnly  = true
      }]
    })
  ]

  depends_on = [
    helm_release.cilium,
    kubernetes_config_map_v1_data.kubelet_config,
  ]
}
