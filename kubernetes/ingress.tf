
resource "kubernetes_namespace_v1" "traefik" {
  metadata {
    name = "traefik"
  }
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = kubernetes_namespace_v1.traefik.metadata[0].name
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"

  # Pin a chart version after checking the version
  # currently installed in your cluster.
  version = "41.7.1"

  values = [
    yamlencode({
      deployment = {
        replicas = 3
      }

      service = {
        type = "LoadBalancer"
        spec = {
          loadBalancerIP = "192.168.1.241"
        }
      }

      providers = {
        kubernetesIngress = {
          enabled      = true
          ingressClass = "traefik"
        }
        kubernetesCRD = {
          enabled = true
        }
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.traefik,
    helm_release.cilium,
  ]
}
