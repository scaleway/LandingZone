output "zone_ids" {
  description = "Map of created DNS zone IDs (subdomain.domain format)."
  value       = { for k, v in scaleway_domain_zone.zones : k => v.id }
}

output "zone_nameservers" {
  description = "Map of DNS zone nameservers."
  value       = { for k, v in scaleway_domain_zone.zones : k => v.ns }
}

output "record_ids" {
  description = "Map of created DNS record IDs."
  value       = { for k, v in scaleway_domain_record.records : k => v.id }
}