output "vpn_gateway_ids" {
  description = "Map of VPN gateway IDs."
  value       = { for k, v in scaleway_s2s_vpn_gateway.this : k => v.id }
}

output "vpn_gateway_statuses" {
  description = "Map of VPN gateway statuses."
  value       = { for k, v in scaleway_s2s_vpn_gateway.this : k => v.status }
}

output "vpn_gateway_asns" {
  description = "Map of VPN gateway ASNs (Scaleway side, typically 12876)."
  value       = { for k, v in scaleway_s2s_vpn_gateway.this : k => v.asn }
}

output "customer_gateway_ids" {
  description = "Map of customer gateway IDs."
  value       = { for k, v in scaleway_s2s_vpn_customer_gateway.this : k => v.id }
}

output "routing_policy_ids" {
  description = "Map of routing policy IDs (IPv4 and IPv6 combined)."
  value = merge(
    { for k, v in scaleway_s2s_vpn_routing_policy.ipv4 : k => v.id },
    { for k, v in scaleway_s2s_vpn_routing_policy.ipv6 : k => v.id }
  )
}

output "connection_ids" {
  description = "Map of VPN connection IDs."
  value       = { for k, v in scaleway_s2s_vpn_connection.this : k => v.id }
}

output "connection_statuses" {
  description = "Map of VPN connection statuses."
  value       = { for k, v in scaleway_s2s_vpn_connection.this : k => v.status }
}

output "tunnel_statuses" {
  description = "Map of IPSec tunnel statuses."
  value       = { for k, v in scaleway_s2s_vpn_connection.this : k => v.tunnel_status }
}

output "bgp_statuses" {
  description = "Map of BGP session statuses."
  value = {
    for k, v in scaleway_s2s_vpn_connection.this : k => (
      lookup(v, "bgp_status_ipv4", null) != null ? v.bgp_status_ipv4 : lookup(v, "bgp_status_ipv6", null)
    )
  }
}

output "secret_ids" {
  description = "Map of terraform-owned Secret Manager secret IDs containing the PSK for each connection (destroyed with the connection)."
  value       = { for k, v in scaleway_secret.psk : k => v.id }
}

output "secret_versions" {
  description = "Map of terraform-owned Secret Manager secret version revisions for the PSK."
  value       = { for k, v in scaleway_secret_version.psk : k => v.revision }
}