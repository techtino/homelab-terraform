locals {
  default_ssh_public_key_paths = [
    pathexpand("~/.ssh/id_ed25519.pub"),
    pathexpand("~/.ssh/id_rsa.pub"),
  ]

  discovered_ssh_public_keys = distinct(flatten([
    for path in local.default_ssh_public_key_paths : fileexists(path) ? [trimspace(file(path))] : []
  ]))

  ssh_public_keys = var.ssh_public_keys != null ? var.ssh_public_keys : local.discovered_ssh_public_keys

  kubernetes_vms = {
    control = {
      name   = "k8s-control"
      vm_id  = 106
      role   = "control"
      master = true
    }
    worker1 = {
      name   = "k8s-worker1"
      vm_id  = 107
      role   = "worker"
      master = false
    }
    worker2 = {
      name   = "k8s-worker2"
      vm_id  = 108
      role   = "worker"
      master = false
    }
  }

  kubernetes_ipv4_addresses = {
    for name, vm in module.kubernetes_vm : name => one(flatten([
      for address_group in vm.ipv4_addresses : [
        for address in address_group : address if can(regex("^192\\.168\\.1\\.", address))
      ]
    ]))
  }
}

module "kubernetes_vm" {
  for_each = local.kubernetes_vms
  source   = "./modules/vm"

  vm_name                     = each.value.name
  vm_id                       = each.value.vm_id
  node_name                   = var.proxmox_node_name
  cloud_image_id              = proxmox_download_file.debian_cloud_image.id
  vm_datastore_id             = var.vm_datastore_id
  cloud_init_datastore_id     = var.cloud_init_datastore_id
  cloud_init_iso_datastore_id = var.cloud_init_iso_datastore_id
  user_data = templatefile(
    "${path.module}/cloud-init/${each.value.role}.yaml.tftpl",
    {
      hostname            = each.value.name
      master              = each.value.master
      kubernetes_pod_cidr = var.kubernetes_pod_cidr
      ssh_username        = var.ssh_username
      ssh_password_hash   = var.ssh_password_hash
      ssh_public_keys     = local.ssh_public_keys
    }
  )

  vm_cores     = var.vm_cores
  vm_memory_mb = var.vm_memory_mb
}

# Join workers after the control-plane cloud-init has generated its runtime
# join command. The token and CA hash are fetched at apply time, not stored in
# Terraform state.
resource "terraform_data" "join_workers" {
  depends_on = [module.kubernetes_vm]

  triggers_replace = [
    for name in keys(local.kubernetes_vms) : local.kubernetes_ipv4_addresses[name]
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      ssh_opts=(-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)
      control_ip='${local.kubernetes_ipv4_addresses.control}'
      worker_ips=(${join(" ", [for name, vm in local.kubernetes_vms : local.kubernetes_ipv4_addresses[name] if vm.role == "worker"])})
      join_file="$${TMPDIR:-/tmp}/kubeadm-join-command.$$.sh"
      trap 'rm -f "$join_file"' EXIT

      for attempt in $(seq 1 90); do
        if ssh "$${ssh_opts[@]}" ${var.ssh_username}@$control_ip \
          'sudo test -s /home/${var.ssh_username}/kubeadm-join-command.sh'; then
          break
        fi
        if [ "$${attempt}" -eq 90 ]; then
          echo "Timed out waiting for the control-plane join command" >&2
          exit 1
        fi
        sleep 10
      done

      ssh "$${ssh_opts[@]}" ${var.ssh_username}@$control_ip \
        'sudo cat /home/${var.ssh_username}/kubeadm-join-command.sh' > "$join_file"

      for worker_ip in "$${worker_ips[@]}"; do
        for attempt in $(seq 1 90); do
          if ssh "$${ssh_opts[@]}" ${var.ssh_username}@$worker_ip \
            'command -v kubeadm >/dev/null && systemctl is-active --quiet containerd'; then
            break
          fi
          if [ "$${attempt}" -eq 90 ]; then
            echo "Timed out waiting for worker $${worker_ip}" >&2
            exit 1
          fi
          sleep 10
        done

        if ssh "$${ssh_opts[@]}" ${var.ssh_username}@$worker_ip \
          'test -f /etc/kubernetes/kubelet.conf'; then
          continue
        fi

        ssh "$${ssh_opts[@]}" ${var.ssh_username}@$worker_ip 'sudo bash -s' < "$join_file"
      done
    EOT
  }
}
