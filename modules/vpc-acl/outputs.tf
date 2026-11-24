output "ids" {
  description = "Map of created VPC ACL IDs."
  value       = { for k, v in scaleway_vpc_acl.this : k => v.id }
}