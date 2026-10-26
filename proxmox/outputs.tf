output "kubernetes_nodes" {
  description = "Kubernetes VM identities in Proxmox"

  value = {
    for key, vm in module.kubernetes_vm : key => {
      name  = vm.name
      vm_id = vm.vm_id
    }
  }
}

output "kubernetes_control_plane_ipv4" {
  description = "Current DHCP address of the Kubernetes control-plane API server."
  value       = local.kubernetes_ipv4_addresses.control
}
