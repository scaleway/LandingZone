variable "region" {
  description = "The region of the VPC connectors."
  type        = string
  default     = "fr-par"
}

variable "peering_connections" {
  description = <<EOF
Map of VPC peering connections to create between VPCs.
Each connection creates a VPC connector and bidirectional routes.

For routes to be created, provide source_vpc_cidr and target_vpc_cidr.
EOF
  type = map(object({
    name            = optional(string)
    source_vpc_id   = string
    target_vpc_id   = string
    source_vpc_cidr = optional(string)
    target_vpc_cidr = optional(string)
    tags            = optional(list(string), [])
  }))
  default = {}
}