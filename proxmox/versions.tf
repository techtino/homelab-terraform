terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://192.168.1.31:8006/"
  insecure  = true
  api_token = var.proxmox_api_token

  ssh {
    username = "root"
    agent    = true
  }
}
