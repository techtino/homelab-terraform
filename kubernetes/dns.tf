resource "opnsense_unbound_host_override" "edge_services" {
  for_each = {
    for domain in flatten([for app in values(local.routed_apps) : app.domains]) : domain => {
      hostname = split(".", domain)[0]
      domain   = join(".", slice(split(".", domain), 1, length(split(".", domain))))
    }
  }

  enabled     = true
  hostname    = each.value.hostname
  domain      = each.value.domain
  server      = local.gateway_ip
  description = "Managed by OpenTofu: ${each.key}"

  lifecycle {
    precondition {
      condition = (
        length(each.key) <= 253 &&
        can(regex("^[a-zA-Z0-9.-]+$", each.key)) &&
        !startswith(each.key, ".") &&
        !endswith(each.key, ".") &&
        !strcontains(each.key, "..") &&
        alltrue([
          for label in split(".", each.key) :
          length(label) >= 1 &&
          length(label) <= 63 &&
          can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$", label))
        ])
      )
      error_message = "Each edge hostname must be a valid hostname, such as app.home.arpa."
    }
  }
}
