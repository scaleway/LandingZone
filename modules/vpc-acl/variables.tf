variable "vpc_id" {
  description = "The ID of the VPC in which to create the ACL."
  type        = string
}

variable "region" {
  description = "The region of the VPC."
  type        = string
  default     = "fr-par"
}

variable "acls" {
  description = <<EOF
Map of VPC Network ACLs to create. Each ACL contains an ordered list of rules.

Rule fields:
  - protocol        Protocol: "ANY", "TCP", "UDP", "ICMP", or "ICMPv6" (default: ANY)
  - source_cidr     Source CIDR (default: 0.0.0.0/0)
  - destination_cidr Destination CIDR (default: 0.0.0.0/0)
  - action          "accept" or "drop"
  - description     Rule description (optional)
  - src_port_low    Start of source port range (optional)
  - src_port_high   End of source port range (optional)
  - dst_port_low    Start of destination port range (optional)
  - dst_port_high   End of destination port range (optional)

ACL-level fields:
  - default_policy   "accept" or "drop" (default: accept)
  - is_ipv6          Whether this ACL is for IPv6 (default: false)
EOF
  type = map(object({
    default_policy = optional(string, "accept")
    is_ipv6        = optional(bool, false)
    rules = optional(list(object({
      protocol         = optional(string, "ANY")
      source_cidr      = optional(string, "0.0.0.0/0")
      destination_cidr = optional(string, "0.0.0.0/0")
      action           = string
      description      = optional(string)
      src_port_low     = optional(number)
      src_port_high    = optional(number)
      dst_port_low     = optional(number)
      dst_port_high    = optional(number)
    })), [])
  }))
  default = {}
}