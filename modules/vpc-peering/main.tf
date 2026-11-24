/**
 * Scaleway VPC Peering Module
 * Creates VPC connectors AND custom routes to enable network connectivity between VPCs.
 *
 * Scaleway peering requires BOTH VPCs to create a connector towards the other.
 * A single connector shows status "orphan" until the matching connector exists.
 *
 * For each peering connection we create:
 *   1. Connector: source VPC => target VPC
 *   2. Connector: target VPC => source VPC
 *   3. Route: source VPC => target CIDR via connector #1
 *   4. Route: target VPC => source CIDR via connector #2
 *
 * For a hub-and-spoke topology:
 *   - Hub VPC must have enable_transitivity = true
 *   - Each spoke creates a connector towards hub, hub creates a connector towards spoke
 *   - Routes direct traffic through the connectors
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

# ---------------------------------------------------------------------------
# VPC Connectors, Source => Target
# ---------------------------------------------------------------------------

resource "scaleway_vpc_connector" "source_to_target" {
  for_each = var.peering_connections

  name          = lookup(each.value, "name", "networking-peering-${each.key}") # TODO: Need to have unique names for source to target and target to source?
  vpc_id        = each.value.source_vpc_id
  target_vpc_id = each.value.target_vpc_id
  tags          = lookup(each.value, "tags", [])
  region        = var.region
}

# ---------------------------------------------------------------------------
# VPC Connectors, Target => Source (required for peering to activate)
# ---------------------------------------------------------------------------

resource "scaleway_vpc_connector" "target_to_source" {
  for_each = var.peering_connections

  name          = lookup(each.value, "name", "networking-peering-${each.key}") # TODO: Need to have unique names for source to target and target to source?
  vpc_id        = each.value.target_vpc_id
  target_vpc_id = each.value.source_vpc_id
  tags          = lookup(each.value, "tags", [])
  region        = var.region
}

# ---------------------------------------------------------------------------
# Routes, Source VPC => Target VPC (via source_to_target connector)
# ---------------------------------------------------------------------------

resource "scaleway_vpc_route" "source_to_target_route" {
  for_each = {
    for k, v in var.peering_connections : k => v
    if lookup(v, "target_vpc_cidr", null) != null
  }

  vpc_id                   = each.value.source_vpc_id
  destination              = each.value.target_vpc_cidr
  nexthop_vpc_connector_id = scaleway_vpc_connector.source_to_target[each.key].id
  tags                     = lookup(each.value, "tags", [])
  region                   = var.region
}

# ---------------------------------------------------------------------------
# Routes, Target VPC => Source VPC (via target_to_source connector)
# ---------------------------------------------------------------------------

resource "scaleway_vpc_route" "target_to_source_route" {
  for_each = {
    for k, v in var.peering_connections : k => v
    if lookup(v, "source_vpc_cidr", null) != null
  }

  vpc_id                   = each.value.target_vpc_id
  destination              = each.value.source_vpc_cidr
  nexthop_vpc_connector_id = scaleway_vpc_connector.target_to_source[each.key].id
  tags                     = lookup(each.value, "tags", [])
  region                   = var.region
}
