output "organization_id" {
  description = "Scaleway Organization ID."
  value       = var.organization_id
}

output "vpc_ids" {
  description = "Map of created VPC IDs."
  value       = { for k, v in module.vpcs : k => v.id }
}

output "vpc_names" {
  description = "Map of created VPC names."
  value       = { for k, v in module.vpcs : k => v.name }
}

output "private_network_ids" {
  description = "Map of Private Network IDs keyed by vpc_key.pn_key."
  value = {
    for vpc_key, vpc in module.vpcs : vpc_key => vpc.private_network_ids
  }
}

output "vpc_peering_ids" {
  description = "Map of created VPC peering connector IDs."
  value       = length(local.vpc_peerings) > 0 ? module.vpc_peerings[0].ids : {}
}

output "vpc_peering_target_to_source_ids" {
  description = "Map of target-to-source VPC peering connector IDs (connectors created in the target VPCs pointing back to the source VPC)."
  value       = length(local.vpc_peerings) > 0 ? module.vpc_peerings[0].target_to_source_ids : {}
}

output "vpc_peering_statuses" {
  description = "Map of created VPC peering connector statuses."
  value       = length(local.vpc_peerings) > 0 ? module.vpc_peerings[0].statuses : {}
}

output "vpc_peering_route_ids" {
  description = "Map of VPC peering route IDs (source_to_target and target_to_source combined)."
  value = length(local.vpc_peerings) > 0 ? merge(
    module.vpc_peerings[0].source_to_target_route_ids,
    module.vpc_peerings[0].target_to_source_route_ids
  ) : {}
}

output "vpc_route_ids" {
  description = "Map of VPC route IDs keyed by vpc_key.route_key."
  value = {
    for k, v in module.vpc_routes : k => v.ids
  }
}

output "vpc_acl_ids" {
  description = "Map of VPC ACL IDs keyed by vpc_key.acl_key."
  value = {
    for k, v in module.vpc_acls : k => v.ids
  }
}

output "public_gateway_ids" {
  description = "Map of created Public Gateway IDs."
  value       = { for k, v in module.public_gateways : k => v.id }
}

output "public_gateway_ips" {
  description = "Map of Public Gateway IP addresses."
  value       = { for k, v in module.public_gateways : k => v.ip_address }
}

output "gateway_network_ids" {
  description = "Map of created GatewayNetwork IDs keyed by gateway_key.gn_key."
  value = {
    for gw_key, gw in module.public_gateways : gw_key => gw.gateway_network_ids
  }
}

output "dns_zone_ids" {
  description = "Map of created DNS zone IDs."
  value       = length(local.dns_zones) > 0 ? module.dns[0].zone_ids : {}
}

output "dns_zone_nameservers" {
  description = "Map of DNS zone nameservers."
  value       = length(local.dns_zones) > 0 ? module.dns[0].zone_nameservers : {}
}

output "dns_record_ids" {
  description = "Map of created DNS record IDs."
  value       = length(local.dns_zones) > 0 ? module.dns[0].record_ids : {}
}

output "firewall_appliance_ids" {
  description = "Map of created firewall appliance instance IDs."
  value       = { for k, v in module.firewall_appliances : k => v.id }
}

output "firewall_appliance_public_ips" {
  description = "Map of firewall appliance public IP addresses."
  value       = { for k, v in module.firewall_appliances : k => v.public_ips }
}

output "firewall_appliance_private_ips" {
  description = "Map of firewall appliance private IP addresses."
  value       = { for k, v in module.firewall_appliances : k => v.private_ips }
}

output "load_balancer_ids" {
  description = "Map of created Load Balancer IDs."
  value       = { for k, v in module.load_balancers : k => v.id }
}

output "load_balancer_ips" {
  description = "Map of Load Balancer public IPv4 addresses."
  value       = { for k, v in module.load_balancers : k => v.ip_address }
}

output "load_balancer_ipv6s" {
  description = "Map of Load Balancer public IPv6 addresses."
  value       = { for k, v in module.load_balancers : k => v.ipv6_address }
}

output "load_balancer_backend_ids" {
  description = "Map of Load Balancer backend IDs keyed by lb_key.backend_key."
  value = {
    for k, v in module.load_balancers : k => v.backend_ids
  }
}

output "load_balancer_frontend_ids" {
  description = "Map of Load Balancer frontend IDs keyed by lb_key.frontend_key."
  value = {
    for k, v in module.load_balancers : k => v.frontend_ids
  }
}
