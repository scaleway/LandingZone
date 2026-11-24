/**
 * Scaleway Instance Security Group Module
 * Creates stateful/stateless security groups with inbound/outbound rules.
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

resource "scaleway_instance_security_group" "this" {
  name                    = var.name
  description             = var.description
  project_id              = var.project_id
  zone                    = var.zone
  stateful                = var.stateful
  inbound_default_policy  = var.inbound_default_policy
  outbound_default_policy = var.outbound_default_policy
  enable_default_security = var.enable_default_security
  tags                    = var.tags

  dynamic "inbound_rule" {
    for_each = { for i, rule in var.inbound_rules : i => rule }
    content {
      action     = inbound_rule.value.action
      protocol   = lookup(inbound_rule.value, "protocol", "TCP")
      port       = lookup(inbound_rule.value, "port", null)
      port_range = lookup(inbound_rule.value, "port_range", null)
      ip_range   = lookup(inbound_rule.value, "ip_range", null)
    }
  }

  dynamic "outbound_rule" {
    for_each = { for i, rule in var.outbound_rules : i => rule }
    content {
      action     = outbound_rule.value.action
      protocol   = lookup(outbound_rule.value, "protocol", "TCP")
      port       = lookup(outbound_rule.value, "port", null)
      port_range = lookup(outbound_rule.value, "port_range", null)
      ip_range   = lookup(outbound_rule.value, "ip_range", null)
    }
  }
}