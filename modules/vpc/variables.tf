variable "name" {
  description = "The name for the VPC."
  type        = string
}

variable "project_id" {
  description = "The ID of the Project the VPC is associated with. Defaults to the provider's project if not set."
  type        = string
  default     = null
}

variable "region" {
  description = "The region of the VPC."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "The tags to associate with the VPC."
  type        = list(string)
  default     = []
}

variable "enable_routing" {
  description = "Enable routing between Private Networks in the VPC. Cannot be deactivated afterwards."
  type        = bool
  default     = true
}

variable "enable_custom_routes_propagation" {
  description = "Defines whether the VPC advertises custom routes between its Private Networks. Cannot be deactivated afterwards."
  type        = bool
  default     = true
}

variable "enable_transitivity" {
  description = "Enable packets from peered VPCs to transit through this VPC."
  type        = bool
  default     = false
}

variable "private_networks" {
  description = "Map of Private Networks to create within the VPC. Each PN supports optional IPAM IP reservations (`ipam_ips` map). Each IPAM IP supports: name (optional, defaults to key), address (optional, auto-allocated if omitted), is_ipv6 (optional, default false), and tags."
  type = map(object({
    name              = string
    ipv4_subnet_cidr  = optional(string)
    ipv6_subnet_cidrs = optional(list(string), [])
    tags              = optional(list(string), [])
    ipam_ips          = optional(map(any), {})
  }))
  default = {}
}

# --------------------------------------------------------------------------
# Factory-style IAM Policies - one-call IAM wiring (per-VPC)
# --------------------------------------------------------------------------

variable "iam_policies" {
  description = "Map of IAM policies to create for this VPC (factory-style). Each key is the policy key; each value supports: name (optional, defaults to key), description, tags, user_id/group_id/application_id/no_principal, and rules (list of { organization_id, project_ids, permission_set_names, condition }). Rules automatically include this VPC's project_id when project_ids is empty."
  type        = any
  default     = {}
}

variable "organization_id" {
  description = "The organization ID used as default context for inline IAM policies. When not set, policies must provide organization_id in rules."
  type        = string
  default     = null
}

# --------------------------------------------------------------------------
# Factory-style Security Groups - create SGs scoped to the VPC's project
# --------------------------------------------------------------------------

variable "security_groups" {
  description = "Map of security groups to create alongside the VPC (factory-style). Each value supports: name (optional, defaults to key), description, stateful, inbound/outbound default policies, enable_default_security, zone, tags, and inbound_rules/outbound_rules (list of { action, protocol, port, port_range, ip_range })."
  type        = any
  default     = {}
}

variable "zone" {
  description = "Default zone for security groups created by this module (e.g. fr-par-2)."
  type        = string
  default     = null
}
