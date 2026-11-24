/**
 * Scaleway Public Gateway Module
 * Creates a Public Gateway with flexible IP, and GatewayNetwork connections
 * to attach Private Networks (NAT/egress, bastion support).
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
}

resource "scaleway_vpc_public_gateway_ip" "this" {
  count      = var.create_ip ? 1 : 0
  reverse    = var.ip_reverse
  tags       = var.tags
  project_id = var.project_id
  zone       = var.zone
}

resource "scaleway_vpc_public_gateway" "this" {
  name              = var.name
  type              = var.type
  tags              = var.tags
  project_id        = var.project_id
  zone              = var.zone
  ip_id             = var.create_ip ? scaleway_vpc_public_gateway_ip.this[0].id : var.ip_id
  bastion_enabled   = var.bastion_enabled
  bastion_port      = var.bastion_enabled ? var.bastion_port : null
  allowed_ip_ranges = var.bastion_enabled ? var.allowed_ip_ranges : []
  enable_smtp       = var.enable_smtp
}

resource "scaleway_vpc_gateway_network" "attachments" {
  for_each = var.gateway_networks

  gateway_id         = scaleway_vpc_public_gateway.this.id
  private_network_id = each.value.private_network_id
  enable_masquerade  = lookup(each.value, "enable_masquerade", true)
  zone               = var.zone

  ipam_config {
    push_default_route = lookup(each.value, "push_default_route", true)
  }
}