/**
 * Scaleway VPC Route Module
 * Creates custom routes in a VPC to direct traffic to specific next hops.
 *
 * Next hop types supported:
 *   - VPC connector (peering), nexthop_vpc_connector_id
 *   - Instance NIC (firewall), nexthop_resource_id (instance + nic)
 *   - Private Network, nexthop_private_network_id
 *
 * Required for:
 *   - VPC peering traffic flow (routes in both VPCs pointing at connector)
 *   - Firewall appliance redirection (routes pointing at instance NIC)
 *   - VPN gateway traffic (routes pointing at VPN gateway's private network)
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

resource "scaleway_vpc_route" "this" {
  for_each = var.routes

  vpc_id      = var.vpc_id
  destination = each.value.destination
  tags        = lookup(each.value, "tags", [])
  region      = var.region

  # Next hop: VPC connector (peering)
  nexthop_vpc_connector_id = lookup(each.value, "nexthop_vpc_connector_id", null)

  # Next hop: Instance NIC (firewall/VPN gateway)
  nexthop_resource_id = lookup(each.value, "nexthop_resource_id", null)

  # Next hop: Private Network
  nexthop_private_network_id = lookup(each.value, "nexthop_private_network_id", null)
}