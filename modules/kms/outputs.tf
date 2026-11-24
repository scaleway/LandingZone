output "id" {
  description = "ID of the created KMS key."
  value       = scaleway_key_manager_key.this.id
}

output "name" {
  description = "Name of the created KMS key."
  value       = scaleway_key_manager_key.this.name
}
