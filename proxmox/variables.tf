variable "vm_cores" {
  description = "Number of vCPUs per Kubernetes VM"
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Memory in MiB per Kubernetes VM"
  type        = number
  default     = 4096
}

variable "kubernetes_pod_cidr" {
  description = "Pod network CIDR passed to kubeadm init on the master node."
  type        = string
  default     = "10.244.0.0/16"
}

variable "proxmox_node_name" {
  description = "Proxmox node on which the Kubernetes VMs are created."
  type        = string
  default     = "techtino-proxmox"
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the form user@realm!tokenid=secret."
  type        = string
  sensitive   = true
}

variable "vm_datastore_id" {
  description = "Datastore for VM disks and EFI state."
  type        = string
  default     = "truenas-nvme"
}

variable "cloud_image_datastore_id" {
  description = "File-based datastore used to download the Debian cloud image."
  type        = string
  default     = "local"
}

variable "cloud_init_datastore_id" {
  description = "Datastore with snippets enabled for cloud-init userdata."
  type        = string
  default     = "local"
}

variable "cloud_init_iso_datastore_id" {
  description = "Datastore for the generated cloud-init ISO attached to each VM."
  type        = string
  default     = "local-lvm"
}

variable "debian_cloud_image_url" {
  description = "Debian 13 (Trixie) generic amd64 cloud image URL."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}

variable "debian_cloud_image_checksum" {
  description = "Optional SHA-256 checksum for the Debian cloud image."
  type        = string
  default     = null
}

variable "ssh_username" {
  description = "Administrative Linux user created by cloud-init."
  type        = string
  default     = "techtino"
}

variable "ssh_password_hash" {
  description = "SHA-512 crypt password hash for the administrative user."
  type        = string
  sensitive   = true
}

variable "ssh_public_keys" {
  description = "Optional SSH public keys for the administrative user. When unset, the first existing default key in ~/.ssh is used."
  type        = list(string)
  default     = null
}
