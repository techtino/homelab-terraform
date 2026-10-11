resource "proxmox_download_file" "debian_cloud_image" {
  content_type       = "import"
  datastore_id       = var.cloud_image_datastore_id
  node_name          = var.proxmox_node_name
  file_name          = "debian-13-generic-amd64.qcow2"
  overwrite          = false
  url                = var.debian_cloud_image_url
  checksum           = var.debian_cloud_image_checksum
  checksum_algorithm = var.debian_cloud_image_checksum == null ? null : "sha256"
}