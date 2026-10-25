variable "opnsense_uri" {
  description = "OPNsense API base URL"
  type        = string
  default     = "https://192.168.1.1"
}

variable "opnsense_api_key" {
  description = "OPNsense API key"
  type        = string
  sensitive   = true
}

variable "opnsense_api_secret" {
  description = "OPNsense API secret"
  type        = string
  sensitive   = true
}

variable "cilium_k8s_api_port" {
  description = "Port of the Kubernetes control-plane API server, used by Cilium without kube-proxy."
  type        = number
  default     = 6443
}
