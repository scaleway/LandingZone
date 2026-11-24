output "probe_endpoint" {
  description = "Private endpoint of the drill probe (invoke with X-Auth-Token of the backup SA)."
  value       = module.fw_probe.endpoint
}

output "probe_container_id" {
  description = "ID of the drill probe container."
  value       = module.fw_probe.id
}

output "drill_vpc_id" {
  description = "ID of the drill VPC."
  value       = module.drill_vpc.id
}

output "drill_lan_pn_id" {
  description = "ID of the drill LAN private network."
  value       = module.drill_vpc.private_network_ids["lan"]
}

output "drill_fw_passive_id" {
  description = "ID of the restored passive instance (drill)."
  value       = module.fw_restore.fw_passive_instance_id
}

output "drill_fw_active_id" {
  description = "ID of the restored active instance (drill)."
  value       = module.fw_restore.fw_active_instance_id
}
