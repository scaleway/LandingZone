output "organization_id" {
  description = "Scaleway Organization ID."
  value       = var.organization_id
}

output "cockpit_source_ids" {
  description = "Map of created Cockpit source IDs."
  value = merge([
    for k, v in module.cockpit : v.source_ids
  ]...)
}

output "cockpit_source_urls" {
  description = "Map of Cockpit source URLs."
  value = merge([
    for k, v in module.cockpit : v.source_urls
  ]...)
}

output "cockpit_source_push_urls" {
  description = "Map of Cockpit source push URLs."
  value = merge([
    for k, v in module.cockpit : v.source_push_urls
  ]...)
}

output "cockpit_token_ids" {
  description = "Map of created Cockpit token IDs."
  value = merge([
    for k, v in module.cockpit : v.token_ids
  ]...)
}

output "cockpit_token_secret_keys" {
  description = "Map of Cockpit token secret keys (sensitive)."
  value = merge([
    for k, v in module.cockpit : v.token_secret_keys
  ]...)
  sensitive = true
}

output "kms_key_ids" {
  description = "Map of created KMS key IDs."
  value       = { for k, v in module.kms_keys : k => v.id }
}

output "secret_ids" {
  description = "Map of created Secret Manager secret IDs."
  value       = { for k, v in module.secrets : k => v.id }
}

output "security_group_ids" {
  description = "Map of created security group IDs."
  value       = { for k, v in module.security_groups : k => v.id }
}
