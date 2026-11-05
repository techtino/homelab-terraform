
# Installed here rather than by Argo CD: nothing, Argo CD included, can run
# until the cluster has a network. MetalLB is deployed by Argo CD
# (gitops/apps/metallb.yaml).
resource "helm_release" "cilium" {
  name            = "cilium"
  namespace       = "kube-system"
  repository      = "https://helm.cilium.io"
  chart           = "cilium"
  version         = "1.18.3"
  upgrade_install = true
  wait            = true
  atomic          = true
  timeout         = 900

  values = [
    yamlencode({
      operator = {
        replicas = 2
      }

      # kubeadm is configured to skip its kube-proxy addon. Keep these API
      # server coordinates reachable directly while Cilium starts up.
      kubeProxyReplacement = true
      k8sServiceHost       = data.terraform_remote_state.proxmox.outputs.kubernetes_control_plane_ipv4
      k8sServicePort       = 6443

      # Hubble itself is on by default; Relay aggregates flows from every node
      # and the UI is exposed through the gateway (routes.tf).
      hubble = {
        relay = { enabled = true }
        ui    = { enabled = true }
      }
    })
  ]
}
