resource "proxmox_virtual_environment_file" "user_data" {
  count = var.user_data == null ? 0 : 1

  # Cloud-init is consumed during first boot. Updating the snippet does not
  # re-run cloud-init inside an existing VM, so preserve the live snippet until
  # a deliberate VM rebuild is requested.
  lifecycle {
    ignore_changes = [source_raw]
  }

  content_type = "snippets"
  datastore_id = var.cloud_init_datastore_id
  node_name    = var.node_name

  source_raw {
    data      = var.user_data
    file_name = "${var.vm_name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  acpi                                 = true
  bios                                 = "ovmf"
  boot_order                           = ["scsi0", "net0"]
  delete_unreferenced_disks_on_destroy = true
  keyboard_layout                      = "en-us"
  machine                              = "q35"
  on_boot                              = true
  reboot_after_update                  = true
  scsi_hardware                        = "virtio-scsi-single"
  started                              = true
  stop_on_destroy                      = false
  tablet_device                        = true
  timeout_clone                        = 1800
  timeout_create                       = 1800
  timeout_migrate                      = 1800
  timeout_reboot                       = 1800
  timeout_shutdown_vm                  = 1800
  timeout_start_vm                     = 1800
  timeout_stop_vm                      = 300
  purge_on_destroy                     = true

  agent {
    enabled = true
    timeout = "15m"
    trim    = false
    type    = "virtio"
  }

  cpu {
    cores   = var.vm_cores
    sockets = 1
    type    = "host"
  }

  efi_disk {
    datastore_id      = var.vm_datastore_id
    file_format       = "raw"
    pre_enrolled_keys = true
    type              = "4m"
  }

  disk {
    datastore_id = var.vm_datastore_id
    import_from  = var.cloud_image_id
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    size         = 40
  }

  initialization {
    datastore_id      = var.cloud_init_iso_datastore_id
    interface         = "ide0"
    user_data_file_id = var.user_data == null ? null : proxmox_virtual_environment_file.user_data[0].id

    dns {
      domain = "home.arpa"
    }

    ip_config {
      ipv4 {
        address = var.ipv4_address
      }
      ipv6 {
        address = "dhcp"
      }
    }

    dynamic "user_account" {
      for_each = var.user_data == null ? [1] : []

      content {
        keys     = []
        password = null
        username = var.ssh_username
      }
    }
  }

  lifecycle {
    ignore_changes = [initialization[0].user_data_file_id]
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  network_device {
    bridge   = var.network_bridge
    firewall = true
    model    = "virtio"
  }

  operating_system {
    type = "l26"
  }
}
