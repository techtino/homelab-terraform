variable "vm_name" {
  description = "Name and hostname identity of the VM."
  type        = string
}

variable "vm_id" {
  description = "Unique Proxmox VM ID."
  type        = number
}

variable "node_name" {
  description = "Proxmox node on which to create the VM."
  type        = string
}

variable "cloud_image_id" {
  description = "Proxmox file ID of the Debian cloud image to import."
  type        = string
}

variable "network_mac_address" {
  description = "Fixed MAC address for the VM network device, or null to generate one."
  type        = string
  default     = null
}

variable "vm_datastore_id" {
  description = "Datastore for cloned VM disks and EFI state."
  type        = string
}

variable "cloud_init_datastore_id" {
  description = "Datastore with snippets enabled for the cloud-init userdata file."
  type        = string
}

variable "cloud_init_iso_datastore_id" {
  description = "Datastore for the generated cloud-init ISO attached to the VM."
  type        = string
}

variable "user_data" {
  description = "Complete cloud-init user-data document, including the #cloud-config header."
  type        = string
}

variable "network_bridge" {
  description = "Proxmox bridge for the VM network device."
  type        = string
  default     = "vmbr0"
}

variable "vm_cores" {
  description = "Number of vCPUs."
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "Dedicated memory in MiB."
  type        = number
  default     = 4096
}
