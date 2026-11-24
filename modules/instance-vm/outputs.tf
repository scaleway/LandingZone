output "id" {
  description = "The ID of the instance"
  value       = var.create_instance ? scaleway_instance_server.this[0].id : null
}

output "name" {
  description = "The name of the instance"
  value       = var.create_instance ? scaleway_instance_server.this[0].name : null
}

output "public_ips" {
  description = "List of public IPs of the instance"
  value       = var.create_instance ? scaleway_instance_server.this[0].public_ips : []
}

# DHCP (non-pinned) NICs read their IPv4 back via this data source (pinned
# NICs take v.ipam_ip directly, so they never hard-fail a plan). It must
# depend on the NIC resource: on a fresh create it would otherwise race the
# attach and fail to find the NIC.
data "scaleway_instance_private_nic" "this" {
  for_each = var.create_instance ? { for k, v in var.private_networks : k => v if v.ipam_ip == null } : {}

  depends_on = [scaleway_instance_private_nic.this]

  server_id          = scaleway_instance_server.this[0].id
  private_network_id = each.value.pn_id
  zone               = var.zone
}

output "private_ips" {
  description = "List of private IPv4 addresses of the instance"
  value = var.create_instance ? [
    for k, v in var.private_networks :
    v.ipam_ip != null ? v.ipam_ip : try([for ip in data.scaleway_instance_private_nic.this[k].private_ips : ip.address if !startswith(ip.address, "fd")][0], "")
  ] : []
}

output "private_ips_map" {
  description = "Map of private IPv4 addresses keyed by private network name"
  value = var.create_instance ? {
    for k, v in var.private_networks :
    k => v.ipam_ip != null ? v.ipam_ip : try([for ip in data.scaleway_instance_private_nic.this[k].private_ips : ip.address if !startswith(ip.address, "fd")][0], "")
  } : {}
}

output "ip_ids" {
  description = "Map of IP resource IDs"
  value       = { for k, v in scaleway_instance_ip.this : k => v.id }
}

output "private_nic_ids" {
  description = "Map of private-NIC resource IDs keyed by private network key (usable as `nexthop_resource_id` in VPC routes pointing at this instance)."
  value = var.create_instance ? {
    for k, v in scaleway_instance_private_nic.this : k => v.id
  } : {}
}
