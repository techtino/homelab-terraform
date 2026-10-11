output "name" {
  description = "The VM name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "vm_id" {
  description = "The Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_addresses" {
  description = "IPv4 addresses reported by the Proxmox guest agent."
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "user_data_file_id" {
  description = "The uploaded Proxmox cloud-init snippet ID."
  value       = var.user_data == null ? null : proxmox_virtual_environment_file.user_data[0].id
}
