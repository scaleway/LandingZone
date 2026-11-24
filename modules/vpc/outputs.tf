output "id" {
  description = "The ID of the VPC."
  value       = scaleway_vpc.this.id
}

output "name" {
  description = "The name of the VPC."
  value       = scaleway_vpc.this.name
}

output "project_id" {
  description = "The project ID of the VPC (null if using provider default)."
  value       = var.project_id
}

output "private_network_ids" {
  description = "Map of created Private Network IDs."
  value       = { for k, v in scaleway_vpc_private_network.networks : k => v.id }
}

output "private_network_names" {
  description = "Map of created Private Network names."
  value       = { for k, v in scaleway_vpc_private_network.networks : k => v.name }
}

output "ipam_ip_ids" {
  description = "Map of IPAM IP reservation IDs (keyed by `pn_key.ipam_key`)."
  value       = { for k, v in scaleway_ipam_ip.this : k => v.id }
}

output "ipam_ip_addresses" {
  description = "Map of IPAM IP reservation addresses (keyed by `pn_key.ipam_key`)."
  value       = { for k, v in scaleway_ipam_ip.this : k => v.address }
}

output "iam_policy_ids" {
  description = "Map of IAM policy IDs created for this VPC (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.id }
}

output "iam_policy_names" {
  description = "Map of IAM policy names created for this VPC (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.name }
}

output "security_group_ids" {
  description = "Map of Security Group IDs created for this VPC (keyed by SG key)."
  value       = { for k, v in scaleway_instance_security_group.this : k => v.id }
}

output "security_group_names" {
  description = "Map of Security Group names created for this VPC (keyed by SG key)."
  value       = { for k, v in scaleway_instance_security_group.this : k => v.name }
}
