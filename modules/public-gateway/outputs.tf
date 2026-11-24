output "id" {
  description = "The ID of the Public Gateway."
  value       = scaleway_vpc_public_gateway.this.id
}

output "name" {
  description = "The name of the Public Gateway."
  value       = scaleway_vpc_public_gateway.this.name
}

output "ip_id" {
  description = "The ID of the Public Gateway IP."
  value       = var.create_ip ? scaleway_vpc_public_gateway_ip.this[0].id : var.ip_id
}

output "ip_address" {
  description = "The public IP address of the gateway."
  value       = var.create_ip ? scaleway_vpc_public_gateway_ip.this[0].address : null
}

output "gateway_network_ids" {
  description = "Map of created GatewayNetwork IDs."
  value       = { for k, v in scaleway_vpc_gateway_network.attachments : k => v.id }
}