variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

# ---------------------------------------------------------------------------
# Common resource tags (var.common_tags): the org's own tagging policy, fed
# into module "common_tags" (modules/tags), which appends the toolkit-reserved
# markers managed-by / env / stage on top (single source of truth). Validation
# lives in that module too: keys/values with '=' or ':' are rejected, and the
# reserved keys cannot be set by users.
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Org-wide resource tags (key=value) applied to every resource this stage creates, in addition to the toolkit-reserved managed-by/env/stage markers (applied by modules/tags)."
  type        = map(string)
  default     = {}
}

variable "project_key" {
  description = "Key of the project from bootstrap to deploy networking resources into (e.g., networking, dev, prod)."
  type        = string
}

variable "region" {
  description = "Scaleway default region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway default zone."
  type        = string
  default     = "fr-par-2"
}

variable "vpcs" {
  description = "Map of VPCs to create with their Private Networks."
  type = map(object({
    name                             = string
    tags                             = optional(list(string), [])
    enable_routing                   = optional(bool, true)
    enable_custom_routes_propagation = optional(bool, true)
    enable_transitivity              = optional(bool, false)
    private_networks = optional(map(object({
      name              = string
      ipv4_subnet_cidr  = optional(string)
      ipv6_subnet_cidrs = optional(list(string), [])
      tags              = optional(list(string), [])
    })), {})
  }))
  default = {}
}

variable "vpc_peerings" {
  description = "Map of VPC peering connections (connectors) to create between VPCs. Uses source_vpc_key and target_vpc_key to reference VPCs from var.vpcs. Provide source_vpc_cidr and target_vpc_cidr to enable automatic bidirectional route creation."
  type = map(object({
    name            = optional(string)
    source_vpc_key  = string
    target_vpc_key  = string
    source_vpc_cidr = optional(string)
    target_vpc_cidr = optional(string)
    tags            = optional(list(string), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# VPC Routes
# ---------------------------------------------------------------------------

variable "vpc_routes" {
  description = "Map of VPC route collections. Each entry references a VPC by key and defines routes with next hops (connectors, instance NICs, or private networks)."
  type = map(object({
    vpc_key = string
    routes = optional(map(object({
      destination                 = string
      nexthop_vpc_connector_key   = optional(string)
      nexthop_vpc_connector_id    = optional(string)
      nexthop_resource_id         = optional(string)
      nexthop_private_network_key = optional(string)
      nexthop_private_network_id  = optional(string)
      tags                        = optional(list(string), [])
    })), {})
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# VPC ACLs
# ---------------------------------------------------------------------------

variable "vpc_acls" {
  description = "Map of VPC ACL collections. Each entry references a VPC by key and defines ACLs with ordered rules for traffic filtering between Private Networks."
  type = map(object({
    vpc_key = string
    acls = optional(map(object({
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
    })), {})
  }))
  default = {}
}

variable "public_gateways" {
  description = "Map of Public Gateways to create."
  type = map(object({
    name              = string
    type              = optional(string, "VPC-GW-S")
    tags              = optional(list(string), [])
    create_ip         = optional(bool, true)
    ip_id             = optional(string)
    ip_reverse        = optional(string)
    bastion_enabled   = optional(bool, false)
    bastion_port      = optional(number, 61000)
    allowed_ip_ranges = optional(list(string), [])
    enable_smtp       = optional(bool, false)
    gateway_networks = optional(map(object({
      vpc_key             = string
      private_network_key = string
      enable_masquerade   = optional(bool, true)
      push_default_route  = optional(bool, true)
    })), {})
  }))
  default = {}
}

variable "dns_zones" {
  description = "Map of DNS zones to create."
  type = map(object({
    domain    = string
    subdomain = string
  }))
  default = {}
}

variable "dns_records" {
  description = "Map of DNS records to create."
  type = map(object({
    zone_key = string
    name     = string
    type     = string
    data     = string
    ttl      = optional(number, 3600)
    priority = optional(number, 0)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Firewall Appliances
# ---------------------------------------------------------------------------

variable "firewall_appliances" {
  description = "Map of firewall appliance VMs to create in Private Networks."
  type = map(object({
    name                = string
    instance_type       = string
    image               = string
    security_group_key  = string
    vpc_key             = string
    private_network_key = string
    enable_dynamic_ip   = optional(bool, false)
    zone                = optional(string)
    state               = optional(string, "started")
    boot_type           = optional(string, "local")
    protected           = optional(bool, false)
    tags                = optional(list(string), [])
    root_volume = optional(object({
      size_in_gb            = optional(number)
      volume_type           = optional(string)
      delete_on_termination = optional(bool)
      sbs_iops              = optional(number)
      volume_id             = optional(string)
    }))
    user_data = optional(map(string), {})
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Load Balancers
# ---------------------------------------------------------------------------

variable "load_balancers" {
  description = "Map of Load Balancers to create with backends, frontends, and ACLs."
  type = map(object({
    name       = string
    type       = optional(string, "LB-S")
    tags       = optional(list(string), [])
    ip_reverse = optional(string)
    release_ip = optional(bool, false)
    zone       = optional(string)

    backends = optional(map(object({
      name                     = optional(string)
      forward_protocol         = string
      forward_port             = number
      algorithm                = optional(string)
      sticky_sessions          = optional(string)
      server_ips               = optional(list(string), [])
      backend_instance_key     = optional(string) # resolve IPs from this module.firewall_appliances instance
      proxy_protocol           = optional(string)
      timeout_server           = optional(string)
      timeout_connect          = optional(string)
      timeout_tunnel           = optional(string)
      on_marked_down_action    = optional(string)
      ignore_ssl_server_verify = optional(bool, false)
      redispatch_attempt_count = optional(number)
      max_retries              = optional(number)
      ssl_bridging             = optional(bool, false)
      health_check = optional(object({
        check_max_retries     = optional(number)
        check_timeout         = optional(string)
        check_delay           = optional(string)
        port                  = optional(number)
        check_send_proxy      = optional(bool, false)
        transient_check_delay = optional(string)
        http_config = optional(object({
          uri    = string
          method = optional(string)
          code   = optional(string)
          host   = optional(string)
        }))
      }))
    })), {})

    frontends = optional(map(object({
      name               = optional(string)
      backend_key        = string
      inbound_port       = number
      timeout_client     = optional(string)
      enable_ssl         = optional(bool, false)
      ssl_certificate_id = optional(string)
    })), {})

    acls = optional(map(object({
      name         = optional(string)
      frontend_key = string
      index        = optional(number, 0)
      action = optional(object({
        type = string
        redirect = optional(object({
          type   = optional(string)
          target = optional(string)
          code   = optional(number)
        }))
      }), { type = "allow" })
      match = optional(object({
        ip_subnet          = optional(list(string), [])
        http_filter        = optional(string)
        http_filter_value  = optional(list(string))
        http_filter_option = optional(string)
      }), {})
    })), {})
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Remote State Backend Config (from bootstrap)
# ---------------------------------------------------------------------------
variable "state_bucket" {
  description = "Name of the Terraform state bucket (created by bootstrap)."
  type        = string
  default     = ""
}

variable "state_endpoint" {
  description = "Endpoint of the S3-compatible state bucket."
  type        = string
  default     = ""
}

variable "state_access_key" {
  description = "Access key for the state bucket."
  type        = string
  default     = ""
}

variable "state_secret_key" {
  description = "Secret key for the state bucket."
  type        = string
  default     = ""
}

variable "stage0_state_path" {
  description = "Path (relative to this stage dir) of the bootstrap LOCAL state file - source of project_ids, ssh_public_keys, environment. Written by bootstrap into remote_state-<env>.tfvars."
  type        = string
}
