
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
        replicas = 2
      }

      # External services (proxmox, router, truenas) use self-signed certs.
      additionalArguments = ["--serversTransport.insecureSkipVerify=true"]

      service = {
        type = "LoadBalancer"
        spec = {
          loadBalancerIP = local.gateway_ip
        }
      }

      ports = {
        web = {
          http = {
            redirections = {
              entryPoint = {
                to        = "websecure"
                scheme    = "https"
                permanent = true
              }
            }
          }
        }
      }

      providers = {
        kubernetesIngress = {
          enabled = false
        }
        kubernetesGateway = {
          enabled = true
        }
        kubernetesCRD = {
          enabled = false
        }
      }

      gateway = {
        enabled = true
        name    = "traefik-gateway"
        listeners = {
          web = {
            port     = 8000
            protocol = "HTTP"
            namespacePolicy = {
              from = "All"
            }
          }
          websecure = {
            port     = 8443
            protocol = "HTTPS"
            mode     = "Terminate"
            namespacePolicy = {
              from = "All"
            }
            certificateRefs = [
              for name in keys(local.routed_apps) : {
                kind = "Secret"
                name = "${name}-tls"
              }
            ]
          }
        }
      }
    })
  ]

  depends_on = [
    helm_release.cilium,
    kubectl_manifest.gateway_api_crds,
    kubectl_manifest.certificates,
  ]
}


locals {
  gateway_ip = "192.168.1.241"
}

