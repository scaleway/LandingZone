output "ids" {
  description = "Map of source-to-target VPC connector IDs."
  value       = { for k, v in scaleway_vpc_connector.source_to_target : k => v.id }
}

output "target_to_source_ids" {
  description = "Map of target-to-source VPC connector IDs."
  value       = { for k, v in scaleway_vpc_connector.target_to_source : k => v.id }
}

output "names" {
  description = "Map of source-to-target VPC connector names."
  value       = { for k, v in scaleway_vpc_connector.source_to_target : k => v.name }
}

output "statuses" {
  description = "Map of source-to-target VPC connector statuses."
  value       = { for k, v in scaleway_vpc_connector.source_to_target : k => v.status }
}

output "source_to_target_route_ids" {
  description = "Map of route IDs directing traffic from source VPC to target VPC."
  value       = { for k, v in scaleway_vpc_route.source_to_target_route : k => v.id }
}

output "target_to_source_route_ids" {
  description = "Map of route IDs directing traffic from target VPC to source VPC."
  value       = { for k, v in scaleway_vpc_route.target_to_source_route : k => v.id }
}
