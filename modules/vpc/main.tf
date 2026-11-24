/**
 * Scaleway VPC Module
 * Creates a VPC with optional Private Networks (with subnets).
 * Supports hub-and-spoke design via enable_routing.
 * Optional factory-style IAM policies and security groups (one-call wiring).
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

resource "scaleway_vpc" "this" {
  name                             = var.name
  tags                             = var.tags
  project_id                       = var.project_id
  region                           = var.region
  enable_routing                   = var.enable_routing
  enable_custom_routes_propagation = var.enable_custom_routes_propagation
  enable_transitivity              = var.enable_transitivity
}

resource "scaleway_vpc_private_network" "networks" {
  for_each = var.private_networks

  name       = each.value.name
  vpc_id     = scaleway_vpc.this.id
  project_id = var.project_id
  region     = var.region
  tags       = lookup(each.value, "tags", [])

  dynamic "ipv4_subnet" {
    for_each = lookup(each.value, "ipv4_subnet_cidr", null) != null ? [1] : []
    content {
      subnet = each.value.ipv4_subnet_cidr
    }
  }

  dynamic "ipv6_subnets" {
    for_each = lookup(each.value, "ipv6_subnet_cidrs", [])
    content {
      subnet = ipv6_subnets.value
    }
  }
}

# ---------------------------------------------------------------------------
# IPAM IP reservations, create reserved IPs scoped to each Private Network
# Supports auto-allocation (when no address is given) or explicit addresses.
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "this" {
  for_each = merge([
    for pn_key, pn in var.private_networks : {
      for ipam_key, ipam_value in lookup(pn, "ipam_ips", {}) :
      "${pn_key}.${ipam_key}" => merge(
        { pn_key = pn_key, ipam_key = ipam_key },
        ipam_value
      )
    }
  ]...)

  address    = lookup(each.value, "address", null)
  is_ipv6    = lookup(each.value, "is_ipv6", false)
  project_id = coalesce(lookup(each.value, "project_id", null), var.project_id)
  region     = var.region
  tags       = compact(coalesce(lookup(each.value, "tags", []), []))

  source {
    private_network_id = scaleway_vpc_private_network.networks[each.value.pn_key].id
  }
}

# ---------------------------------------------------------------------------
# IAM Policies - one-call IAM wiring (factory-style map, per-VPC)
# Rules automatically include the VPC's project_id when project_ids is empty.
# ---------------------------------------------------------------------------
resource "scaleway_iam_policy" "this" {
  for_each = var.iam_policies

  name        = lookup(each.value, "name", each.key)
  description = coalesce(lookup(each.value, "description", null), null)
  tags        = compact(coalesce(lookup(each.value, "tags", []), []))
  organization_id = coalesce(
    lookup(each.value, "organization_id", null),
    var.organization_id,
    null
  )

  # Mutual-exclusive principals: only one of user_id/group_id/application_id
  # should be non-null. no_principal is only true when explicitly set AND
  # no specific principal is provided.
  user_id        = lookup(each.value, "user_id", null)
  group_id       = lookup(each.value, "group_id", null)
  application_id = lookup(each.value, "application_id", null)
  no_principal = (
    coalesce(lookup(each.value, "no_principal", false), false) &&
    lookup(each.value, "user_id", null) == null &&
    lookup(each.value, "group_id", null) == null &&
    lookup(each.value, "application_id", null) == null
  ) ? true : null

  dynamic "rule" {
    for_each = coalesce(lookup(each.value, "rules", []), [])
    content {
      project_ids          = length(coalesce(lookup(rule.value, "project_ids", []), [])) > 0 ? compact(coalesce(lookup(rule.value, "project_ids", []), [])) : (var.project_id != null ? [var.project_id] : [])
      organization_id      = lookup(rule.value, "organization_id", null)
      permission_set_names = compact(coalesce(lookup(rule.value, "permission_set_names", []), []))
      condition            = lookup(rule.value, "condition", null)
    }
  }
}

# ---------------------------------------------------------------------------
# Security Groups - create SGs scoped to the VPC's project (for use by
# instances attached to this VPC's Private Networks)
# ---------------------------------------------------------------------------
resource "scaleway_instance_security_group" "this" {
  for_each = var.security_groups

  name                    = lookup(each.value, "name", each.key)
  description             = lookup(each.value, "description", null)
  project_id              = coalesce(lookup(each.value, "project_id", null), var.project_id)
  zone                    = coalesce(lookup(each.value, "zone", null), var.zone)
  stateful                = lookup(each.value, "stateful", true)
  inbound_default_policy  = lookup(each.value, "inbound_default_policy", "drop")
  outbound_default_policy = lookup(each.value, "outbound_default_policy", "accept")
  enable_default_security = lookup(each.value, "enable_default_security", true)
  tags                    = compact(coalesce(lookup(each.value, "tags", []), []))

  dynamic "inbound_rule" {
    for_each = { for i, rule in coalesce(lookup(each.value, "inbound_rules", []), []) : i => rule }
    content {
      action     = inbound_rule.value.action
      protocol   = lookup(inbound_rule.value, "protocol", "TCP")
      port       = lookup(inbound_rule.value, "port", null)
      port_range = lookup(inbound_rule.value, "port_range", null)
      ip_range   = lookup(inbound_rule.value, "ip_range", null)
    }
  }

  dynamic "outbound_rule" {
    for_each = { for i, rule in coalesce(lookup(each.value, "outbound_rules", []), []) : i => rule }
    content {
      action     = outbound_rule.value.action
      protocol   = lookup(outbound_rule.value, "protocol", "TCP")
      port       = lookup(outbound_rule.value, "port", null)
      port_range = lookup(outbound_rule.value, "port_range", null)
      ip_range   = lookup(outbound_rule.value, "ip_range", null)
    }
  }
}
