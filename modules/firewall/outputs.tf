output "fw_passive_instance_id" {
  description = "ID of passive firewall instance."
  value       = scaleway_instance_server.fw_passive.id
}

output "fw_active_instance_id" {
  description = "ID of active firewall instance."
  value       = scaleway_instance_server.fw_active.id
}

output "fw_passive_wan_ip" {
  value = try(scaleway_ipam_ip.fw_passive_wan[0].address, null)
}

output "fw_passive_lan_ip" {
  value = scaleway_ipam_ip.fw_passive_lan.address
}

output "fw_passive_ha_ip" {
  value = scaleway_ipam_ip.fw_passive_ha.address
}

output "fw_active_wan_ip" {
  value = try(scaleway_ipam_ip.fw_active_wan[0].address, null)
}

output "fw_active_lan_ip" {
  value = scaleway_ipam_ip.fw_active_lan.address
}

output "fw_active_ha_ip" {
  value = scaleway_ipam_ip.fw_active_ha.address
}

output "vip_wan_ip" {
  value = try(scaleway_ipam_ip.vip_wan[0].address, null)
}

output "vip_lan_ip" {
  value = try(scaleway_ipam_ip.vip_lan[0].address, null)
}

output "vip_wan_ipam_id" {
  value = try(scaleway_ipam_ip.vip_wan[0].id, null)
}

output "vip_lan_ipam_id" {
  value = try(scaleway_ipam_ip.vip_lan[0].id, null)
}

output "lan_default_route_id" {
  value = try(scaleway_vpc_route.lan_default_to_fw[0].id, null)
}

output "wan_default_route_id" {
  value = try(scaleway_vpc_route.wan_default_to_fw[0].id, null)
}
