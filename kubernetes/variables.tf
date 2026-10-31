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

variable "truenas_api_key" {
  description = "TrueNAS API key for the CSI driver"
  type        = string
  sensitive   = true
}

variable "basic_auth_htpasswd" {
  description = "htpasswd lines (user:bcrypt-hash, one per line) for routes with auth = true."
  type        = string
  sensitive   = true
}

variable "pushover_user_key" {
  description = "Pushover user or group key that receives Alertmanager notifications."
  type        = string
  sensitive   = true
}

variable "pushover_api_token" {
  description = "Pushover application API token used by Alertmanager."
  type        = string
  sensitive   = true
}

variable "healthchecks_ping_url" {
  description = "healthchecks.io ping URL for the Alertmanager dead man's switch. Empty disables it."
  type        = string
  default     = ""
  sensitive   = true
}
