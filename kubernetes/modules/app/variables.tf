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

variable "replica_count" {
  type        = number
  description = "Number of application replicas."
  default     = 1

  validation {
    condition     = var.replica_count >= 1
    error_message = "replica_count must be at least 1."
  }
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

variable "extra_volumes" {
  type        = map(string)
  description = "Map of Kubernetes node host paths to container mount paths."
  default     = {}
  nullable    = false
}

variable "extra_ports" {
  type = list(object({
    name           = string
    container_port = number
    protocol       = optional(string, "TCP")
  }))

  description = "Additional container and Service ports."
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for p in var.extra_ports :
      can(regex("^[a-z]([-a-z0-9]*[a-z0-9])?$", p.name)) &&
      p.container_port >= 1 &&
      p.container_port <= 65535 &&
      contains(["TCP", "UDP"], p.protocol)
    ])
    error_message = "Extra ports need valid Kubernetes port names, port numbers, and TCP or UDP protocols."
  }
}

