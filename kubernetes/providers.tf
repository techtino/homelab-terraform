
terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.26"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.19"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config")
}

provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/config")
  }
}

provider "opnsense" {
  uri            = var.opnsense_uri
  api_key        = var.opnsense_api_key
  api_secret     = var.opnsense_api_secret
  allow_insecure = true
}

provider "kubectl" {
  config_path = pathexpand("~/.kube/config")
}

data "terraform_remote_state" "proxmox" {
  backend = "local"
  config = {
    path = "${path.module}/../proxmox/terraform.tfstate"
  }
}

data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.3/standard-install.yaml"
}

locals {
  gateway_api_crd_documents = {
    for index, document in split("---", data.http.gateway_api_crds.response_body) :
    tostring(index) => trimspace(document)
    if can(regex("(?m)^apiVersion:", trimspace(document)))
  }
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each  = local.gateway_api_crd_documents
  yaml_body = each.value
}
