output "id" {
  description = "ID of the created secret."
  value       = scaleway_secret.this.id
}

output "name" {
  description = "Name of the created secret."
  value       = scaleway_secret.this.name
}
