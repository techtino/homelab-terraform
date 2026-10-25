output "kubernetes_nodes" {
  description = "Kubernetes VM identities in Proxmox"

  value = {
    control = {
      name  = module.kubernetes_vm["control"].name
      vm_id = module.kubernetes_vm["control"].vm_id
    }

    worker1 = {
      name  = module.kubernetes_vm["worker1"].name
      vm_id = module.kubernetes_vm["worker1"].vm_id
    }

    worker2 = {
      name  = module.kubernetes_vm["worker2"].name
      vm_id = module.kubernetes_vm["worker2"].vm_id
    }

  }
}

output "kubernetes_control_plane_ipv4" {
  description = "Current DHCP address of the Kubernetes control-plane API server."
  value       = local.kubernetes_ipv4_addresses.control
}
