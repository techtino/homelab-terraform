
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

      kubeProxyReplacement = false
    })
  ]
}

resource "helm_release" "metallb" {
  name             = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = "0.16.1"
  wait             = true
  atomic           = true
  timeout          = 600
  depends_on       = [helm_release.cilium]
}

resource "helm_release" "metallb_config" {
  name       = "metallb-config"
  namespace  = "metallb-system"
  chart      = "${path.module}/charts/metallb-config"
  wait       = true
  atomic     = true
  timeout    = 600
  depends_on = [helm_release.metallb]
}
