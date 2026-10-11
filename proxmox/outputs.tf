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

    worker3 = {
      name  = module.kubernetes_vm["worker3"].name
      vm_id = module.kubernetes_vm["worker3"].vm_id
    }

    worker4 = {
      name  = module.kubernetes_vm["worker4"].name
      vm_id = module.kubernetes_vm["worker4"].vm_id
    }
  }
}
