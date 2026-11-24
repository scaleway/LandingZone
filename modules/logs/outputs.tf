output "source_ids" {
  description = "Map of created Cockpit source IDs."
  value       = { for k, v in scaleway_cockpit_source.this : k => v.id }
}

output "source_urls" {
  description = "Map of Cockpit source URLs."
  value       = { for k, v in scaleway_cockpit_source.this : k => v.url }
}

output "source_push_urls" {
  description = "Map of Cockpit source push URLs."
  value       = { for k, v in scaleway_cockpit_source.this : k => v.push_url }
}

output "token_ids" {
  description = "Map of created Cockpit token IDs."
  value       = { for k, v in scaleway_cockpit_token.this : k => v.id }
}

output "token_secret_keys" {
  description = "Map of Cockpit token secret keys (sensitive)."
  value       = { for k, v in scaleway_cockpit_token.this : k => v.secret_key }
  sensitive   = true
}