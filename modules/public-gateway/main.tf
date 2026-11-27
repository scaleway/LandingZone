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
    # Pin a deterministic IPAM IP (e.g. a fixed gateway address that the
    # firewall routes reference). Omit (null) to let the platform auto-assign.
    ipam_ip_id = lookup(each.value, "ipam_ip_id", null)
  }
}

# Inbound PAT (DNAT) rules exposed on this gateway's public IP. Empty map =
# no inbound PAT. The depends_on pins creation AFTER the GatewayNetwork
# attachments exist: the platform validates the private_ip belongs to one of
# the gateway's attached private networks, so a parallel create fails with
# "Gateway has no private network with address <ip>".
resource "scaleway_vpc_public_gateway_pat_rule" "rules" {
  for_each     = var.pat_rules
  gateway_id   = scaleway_vpc_public_gateway.this.id
  zone         = var.zone
  private_ip   = each.value.private_ip
  private_port = each.value.private_port
  public_port  = each.value.public_port
  protocol     = each.value.protocol
  depends_on   = [scaleway_vpc_gateway_network.attachments]
}