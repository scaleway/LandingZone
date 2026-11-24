output "id" {
  description = "The ID of the security group"
  value       = scaleway_instance_security_group.this.id
}

output "name" {
  description = "The name of the security group"
  value       = scaleway_instance_security_group.this.name
}