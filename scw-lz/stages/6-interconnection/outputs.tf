# ---------------------------------------------------------------------------
# Managed Site-to-Site VPN (moved from Stage 2)
# ---------------------------------------------------------------------------

output "s2s_vpn_gateway_ids" {
  description = "Map of S2S VPN gateway IDs."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].vpn_gateway_ids : {}
}

output "s2s_vpn_gateway_asns" {
  description = "Map of S2S VPN gateway ASNs (Scaleway side, typically 12876)."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].vpn_gateway_asns : {}
}

output "s2s_vpn_connection_statuses" {
  description = "Map of S2S VPN connection statuses."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].connection_statuses : {}
}

output "s2s_vpn_tunnel_statuses" {
  description = "Map of IPSec tunnel statuses."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].tunnel_statuses : {}
}

output "s2s_vpn_bgp_statuses" {
  description = "Map of BGP session statuses."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].bgp_statuses : {}
}

output "s2s_vpn_secret_ids" {
  description = "Map of Secret Manager secret IDs containing each connection's PSK."
  value       = length(local.s2s_vpn_connections) > 0 ? module.s2s_vpn[0].secret_ids : {}
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Emulated on-premises site
# ---------------------------------------------------------------------------

output "onprem_vpc_id" {
  description = "ID of the emulated on-premises VPC."
  value       = local.onprem.enabled ? module.onprem_vpc[0].id : null
}

output "onprem_private_network_ids" {
  description = "Map of private-network IDs on the emulated on-premises VPC."
  value       = local.onprem.enabled ? module.onprem_vpc[0].private_network_ids : {}
}

output "onprem_gateway_id" {
  description = "ID of the strongSwan+BIRD on-premises gateway instance."
  value       = local.lab_active ? module.onprem_gateway[0].id : null
}

output "onprem_gateway_public_ip" {
  description = "Public IPv4 of the on-premises gateway (the VPN customer-gateway endpoint)."
  value       = local.lab_active ? scaleway_instance_ip.onprem_pub[0].address : null
}

output "onprem_gateway_private_ip" {
  description = "Private IPv4 of the on-premises gateway on its LAN."
  value       = local.lab_active ? module.onprem_gateway[0].private_ips_map["pn"] : null
}

output "vgw_public_ip" {
  description = "Pinned public IPv4 of the managed VPN gateway (dialed by the on-prem gateway)."
  value       = local.lab_active ? scaleway_ipam_ip.vgw_public[0].address : null
}

output "onprem_vm_ids" {
  description = "Map of emulated on-premises workload VM IDs."
  value       = local.onprem.enabled ? { for k, v in module.onprem_vms : k => v.id } : {}
}
