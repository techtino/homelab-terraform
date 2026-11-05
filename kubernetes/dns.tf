# An OPNsense/Unbound host override pointing each routed name at Traefik.
resource "opnsense_unbound_host_override" "edge_services" {
  for_each = {
    for name in keys(local.routed) : "${name}.${local.domain}" => name
  }

  enabled     = true
  hostname    = each.value
  domain      = local.domain
  server      = local.gateway_ip
  description = "Managed by OpenTofu: ${each.key}"
}
