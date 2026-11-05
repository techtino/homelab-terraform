
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
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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
