output "ids" {
  description = "Map of created VPC route IDs."
  value       = { for k, v in scaleway_vpc_route.this : k => v.id }
}

output "destinations" {
  description = "Map of route destinations."
  value       = { for k, v in scaleway_vpc_route.this : k => v.destination }
}