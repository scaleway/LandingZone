/**
 * Scaleway VPC Network ACL Module
 * Creates Network ACLs for traffic filtering between Private Networks within a VPC.
 *
 * ACLs are stateless rules evaluated in order. Each rule specifies:
 *   - protocol, source/destination CIDR, port ranges, and action (accept/drop)
 *
 * Default policy applies when no rule matches.
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

resource "scaleway_vpc_acl" "this" {
  for_each = var.acls

  vpc_id         = var.vpc_id
  region         = var.region
  default_policy = lookup(each.value, "default_policy", "accept")
  is_ipv6        = lookup(each.value, "is_ipv6", false)

  dynamic "rules" {
    for_each = lookup(each.value, "rules", [])
    content {
      protocol      = lookup(rules.value, "protocol", "ANY")
      source        = lookup(rules.value, "source_cidr", "0.0.0.0/0")
      destination   = lookup(rules.value, "destination_cidr", "0.0.0.0/0")
      action        = rules.value.action
      description   = lookup(rules.value, "description", null)
      src_port_low  = lookup(rules.value, "src_port_low", null)
      src_port_high = lookup(rules.value, "src_port_high", null)
      dst_port_low  = lookup(rules.value, "dst_port_low", null)
      dst_port_high = lookup(rules.value, "dst_port_high", null)
    }
  }
}