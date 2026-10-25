output "name" {
  description = "Application name."
  value       = var.name
}

output "service_name" {
  description = "Internal Kubernetes Service name."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "service_port" {
  description = "Main application Service port."
  value       = var.port
}

output "pvc_name" {
  description = "Persistent volume claim name."
  value       = kubernetes_persistent_volume_claim_v1.this_data.metadata[0].name
}
