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
