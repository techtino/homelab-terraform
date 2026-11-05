# Argo CD deploys everything under gitops/ from the Git repository. OpenTofu
# keeps what has to exist before Argo CD can run (Cilium), what isn't in
# Kubernetes (OPNsense DNS records) and every Secret, so no credentials are
# stored in Git.
#
# The root Application syncs gitops/apps, which holds one Application per
# component (app of apps). Argo CD reads the pushed branch, not this working
# copy: push changes under gitops/ before expecting them in the cluster.

locals {
  gitops_repo_url = "https://github.com/techtino/homelab-terraform.git"
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.14.0"
  timeout    = 900

  values = [
    yamlencode({
      global = {
        domain = "argocd.${local.domain}"
      }

      configs = {
        params = {
          # Traefik terminates TLS (routes.tf).
          "server.insecure" = true
        }
      }

      # Only the built-in admin user is used.
      dex = {
        enabled = false
      }
    })
  ]

  depends_on = [helm_release.cilium]
}

resource "kubectl_manifest" "argocd_root" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "root"
      namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    }
    spec = {
      project = "default"
      source = {
        repoURL        = local.gitops_repo_url
        targetRevision = "main"
        path           = "gitops/apps"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace_v1.argocd.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    # Secrets and namespaces the Argo CD apps expect to exist.
    kubernetes_secret_v1.truenas_api_credentials,
    kubernetes_secret_v1.alertmanager_config,
    kubernetes_secret_v1.grafana_admin,
    kubernetes_secret_v1.basic_auth,
  ]
}
