
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

      additionalArguments = [
        # External services (proxmox, router, truenas) use self-signed certs.
        "--serversTransport.insecureSkipVerify=true",
        # Pick up endpoint changes quickly (default 2s), so a pod that is
        # shutting down stops receiving traffic almost immediately.
        "--providers.providersThrottleDuration=200ms",
        # Fail fast on an unreachable backend (default 30s) so the retry
        # middleware below can try another pod.
        "--serversTransport.forwardingTimeouts.dialTimeout=1s",
      ]

      service = {
        type = "LoadBalancer"
        spec = {
          loadBalancerIP = local.gateway_ip
          # Deliver only to the Traefik pod on the node MetalLB announces from:
          # no extra hop between nodes, and Traefik sees the real client IP.
          externalTrafficPolicy = "Local"
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
        websecure = {
          http = {
            # Strip client-supplied X-Remote-User before basic auth sets it.
            middlewares = [
              "traefik-strip-remote-user@kubernetescrd",
              "traefik-retry@kubernetescrd",
            ]
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
        # Only used for the retry Middleware below.
        kubernetesCRD = {
          enabled = true
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

      # Retry requests that couldn't reach a backend, e.g. a pod on a node that
      # has died but isn't marked NotReady yet. Applied to every route on
      # websecure. Traefik stops as soon as a backend replies (any status), so
      # a request is only re-sent if no backend answered it.
      extraObjects = [
        {
          apiVersion = "traefik.io/v1alpha1"
          kind       = "Middleware"
          metadata = {
            name      = "retry"
            namespace = "traefik"
          }
          spec = {
            retry = {
              attempts        = 3
              initialInterval = "100ms"
            }
          }
        },
        {
          # An empty value removes the header, so apps only ever see the
          # X-Remote-User that basic auth sets (auth.tf).
          apiVersion = "traefik.io/v1alpha1"
          kind       = "Middleware"
          metadata = {
            name      = "strip-remote-user"
            namespace = "traefik"
          }
          spec = {
            headers = {
              customRequestHeaders = {
                "X-Remote-User" = ""
              }
            }
          }
        },
      ]
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

