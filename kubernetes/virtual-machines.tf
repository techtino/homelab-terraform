# Namespace for the KubeVirt VMs deployed by Argo CD
# (gitops/apps/virtual-machines.yaml), and the SSH public keys cloud-init adds
# to them. The keys are read from this workstation, like the Proxmox project
# does, so they aren't stored in Git.
resource "kubernetes_namespace_v1" "vms" {
  metadata {
    name = "vms"
  }
}

locals {
  vm_ssh_public_keys = {
    for path in [pathexpand("~/.ssh/id_ed25519.pub"), pathexpand("~/.ssh/id_rsa.pub")] :
    basename(path) => trimspace(file(path)) if fileexists(path)
  }
}

resource "kubernetes_secret_v1" "vm_ssh_keys" {
  metadata {
    name      = "vm-ssh-keys"
    namespace = kubernetes_namespace_v1.vms.metadata[0].name
  }

  data = local.vm_ssh_public_keys
}
