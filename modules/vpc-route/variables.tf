variable "vpc_id" {
  description = "The ID of the VPC in which to create routes."
  type        = string
}

variable "region" {
  description = "The region of the VPC."
  type        = string
  default     = "fr-par"
}

variable "routes" {
  description = <<EOF
Map of VPC routes to create. Each route directs traffic matching the
destination CIDR to a specific next hop.

Next hop fields (exactly one must be set):
  - nexthop_vpc_connector_id   ID of a VPC peering connector
  - nexthop_resource_id        ID of an instance NIC (firewall, VPN gateway)
  - nexthop_private_network_id ID of a Private Network
EOF
  type = map(object({
    destination                = string
    nexthop_vpc_connector_id   = optional(string)
    nexthop_resource_id        = optional(string)
    nexthop_private_network_id = optional(string)
    tags                       = optional(list(string), [])
  }))
  default = {}
}