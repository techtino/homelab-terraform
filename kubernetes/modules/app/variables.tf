variable "name" {
  type        = string
  description = "Application name; also used for Kubernetes resource names."
}

variable "namespace" {
  type        = string
  description = "Existing Kubernetes namespace."
}

variable "image" {
  type        = string
  description = "Container image, preferably with a pinned tag."
}

variable "port" {
  type        = number
  description = "Main web port used by the container, Service and HTTPRoute."
  default     = 80
  nullable    = false
}

variable "env" {
  type        = map(string)
  description = "Container environment variables."
  default     = {}
  sensitive   = true
  nullable    = false
}

variable "data_size" {
  type        = string
  description = "Size of the application's persistent volume claim."
  default     = "5Gi"
  nullable    = false
}

variable "data_mount_paths" {
  type        = list(string)
  description = "Container paths where the application's PVC is mounted."
  default     = ["/config"]
  nullable    = false
}
