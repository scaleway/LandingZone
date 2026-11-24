output "id" {
  description = "The ID of the Load Balancer"
  value       = var.create_lb ? scaleway_lb.this[0].id : null
}

output "name" {
  description = "The name of the Load Balancer"
  value       = var.create_lb ? scaleway_lb.this[0].name : null
}

output "ip_address" {
  description = "The public IPv4 address of the Load Balancer"
  value       = var.create_lb ? scaleway_lb.this[0].ip_address : null
}

output "ipv6_address" {
  description = "The public IPv6 address of the Load Balancer"
  value       = var.create_lb ? scaleway_lb.this[0].ipv6_address : null
}

output "ip_ids" {
  description = "Map of IP resource IDs"
  value       = { for k, v in scaleway_lb_ip.this : k => v.id }
}

output "backend_ids" {
  description = "Map of backend IDs"
  value       = { for k, v in scaleway_lb_backend.this : k => v.id }
}

output "frontend_ids" {
  description = "Map of frontend IDs"
  value       = { for k, v in scaleway_lb_frontend.this : k => v.id }
}

output "acl_ids" {
  description = "Map of ACL IDs"
  value       = { for k, v in scaleway_lb_acl.this : k => v.id }
}