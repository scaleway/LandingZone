/**
 * Stage 2, Networking
 * Multi-VPC hub-and-spoke design: Private Networks, Public Gateway
 * (NAT/egress), VPC peerings, DNS zones. Site-to-Site VPN lives in Stage 6.
 * Reads bootstrap state for org/project IDs.
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }

  # Use S3-compatible backend for remote state (created by scw-lz/bootstrap).
  # Init with: terraform init -backend-config=../../envs/<env>/backend-<env>.tfvars
  backend "s3" {
    key = "stage-2/terraform.tfstate"
  }

}

# ---------------------------------------------------------------------------
# Remote State, Read project IDs from bootstrap
# ---------------------------------------------------------------------------

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    # bootstrap's local state path (written into remote_state-<env>.tfvars).
    path = var.stage0_state_path
  }
}

# ---------------------------------------------------------------------------
# Common tags: the org's tag policy (var.common_tags) plus the toolkit-
# reserved markers managed-by / env / stage. Composition is the single
# source of truth in modules/tags; local.common_tags below just aliases the
# module output so the rest of this file keeps using local.common_tags.
# ---------------------------------------------------------------------------
module "common_tags" {
  source      = "../../../modules/tags"
  user_tags   = var.common_tags
  environment = local.environment
  stage_id    = "stage2"
}

locals {
  # Project ID + environment from bootstrap's outputs (single source of truth).
  project_id  = data.terraform_remote_state.bootstrap.outputs.project_ids[var.project_key]
  environment = data.terraform_remote_state.bootstrap.outputs.environment

  common_tags = module.common_tags.list

  # YAML factory: per-env data (envs/<env>/data/networking-<env>.yaml, -demo
  # preferred when present); tfvars overrides win.
  factory_file = fileexists("${path.module}/../../envs/${local.environment}/data/networking-${local.environment}-demo.yaml") ? "${path.module}/../../envs/${local.environment}/data/networking-${local.environment}-demo.yaml" : "${path.module}/../../envs/${local.environment}/data/networking-${local.environment}.yaml"

  factory_raw = yamldecode(file(local.factory_file))

  vpcs            = merge(local.factory_raw.vpcs, var.vpcs)
  vpc_peerings    = merge(local.factory_raw.vpc_peerings, var.vpc_peerings)
  vpc_routes      = merge(local.factory_raw.vpc_routes, var.vpc_routes)
  vpc_acls        = merge(local.factory_raw.vpc_acls, var.vpc_acls)
  public_gateways = merge(local.factory_raw.public_gateways, var.public_gateways)
  dns_zones       = merge(local.factory_raw.dns_zones, var.dns_zones)
  dns_records     = merge(local.factory_raw.dns_records, var.dns_records)
  # Optional features: empty/absent = none; try() keeps keys optional in the YAML.
  firewall_appliances = merge(try(local.factory_raw.firewall_appliances, {}), var.firewall_appliances)
  load_balancers      = merge(try(local.factory_raw.load_balancers, {}), var.load_balancers)
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = local.project_id
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# VPCs, Hub + spokes, each with routing and Private Networks
# ---------------------------------------------------------------------------

module "vpcs" {
  source = "../../../modules/vpc"
  for_each = {

    for k, v in local.vpcs : k => v
  }

  name                             = "lz-${local.environment}-vpc-${each.value.name}"
  project_id                       = local.project_id
  region                           = var.region
  tags                             = concat(local.common_tags, lookup(each.value, "tags", []))
  enable_routing                   = lookup(each.value, "enable_routing", true)
  enable_custom_routes_propagation = lookup(each.value, "enable_custom_routes_propagation", true)
  enable_transitivity              = lookup(each.value, "enable_transitivity", false)

  private_networks = {
    for pk, pv in lookup(each.value, "private_networks", {}) : pk => {
      name              = "lz-${local.environment}-pn-${pv.name}"
      ipv4_subnet_cidr  = lookup(pv, "ipv4_subnet_cidr", null)
      ipv6_subnet_cidrs = lookup(pv, "ipv6_subnet_cidrs", [])
      tags              = concat(local.common_tags, lookup(pv, "tags", []))
      ipam_ips          = lookup(pv, "ipam_ips", {})
    }
  }
}

# ---------------------------------------------------------------------------
# VPC Peering, Connect spoke VPCs to the hub VPC
# ---------------------------------------------------------------------------

module "vpc_peerings" {
  source = "../../../modules/vpc-peering"

  count = length(local.vpc_peerings) > 0 ? 1 : 0

  region = var.region

  peering_connections = {

    for k, v in local.vpc_peerings : k => {
      name            = lookup(v, "name", "lz-${local.environment}-peering-${k}")
      source_vpc_id   = module.vpcs[v.source_vpc_key].id
      target_vpc_id   = module.vpcs[v.target_vpc_key].id
      source_vpc_cidr = v.source_vpc_cidr
      target_vpc_cidr = v.target_vpc_cidr
      tags            = concat(local.common_tags, lookup(v, "tags", []))
    }
  }
}

# ---------------------------------------------------------------------------
# VPC Routes, Custom routes for firewalls, VPN gateways, and appliance steering
# ---------------------------------------------------------------------------

module "vpc_routes" {
  source = "../../../modules/vpc-route"
  for_each = {

    for k, v in local.vpc_routes : k => v
  }

  vpc_id = module.vpcs[each.value.vpc_key].id
  region = var.region

  routes = {
    for rk, rv in lookup(each.value, "routes", {}) : rk => {
      destination = rv.destination
      nexthop_vpc_connector_id = lookup(rv, "nexthop_vpc_connector_key", null) != null ? (
        local.vpc_peerings[rv.nexthop_vpc_connector_key].target_vpc_key == each.value.vpc_key
        ? module.vpc_peerings[0].target_to_source_ids[rv.nexthop_vpc_connector_key]
        : module.vpc_peerings[0].ids[rv.nexthop_vpc_connector_key]
      ) : lookup(rv, "nexthop_vpc_connector_id", null)
      nexthop_resource_id        = lookup(rv, "nexthop_resource_id", null)
      nexthop_private_network_id = lookup(rv, "nexthop_private_network_key", null) != null ? module.vpcs[each.value.vpc_key].private_network_ids[rv.nexthop_private_network_key] : lookup(rv, "nexthop_private_network_id", null)
      tags                       = concat(local.common_tags, lookup(rv, "tags", []))
    }
  }
}

# ---------------------------------------------------------------------------
# VPC ACLs, Traffic filtering between Private Networks
# ---------------------------------------------------------------------------

module "vpc_acls" {
  source = "../../../modules/vpc-acl"
  for_each = {

    for k, v in local.vpc_acls : k => v
  }

  vpc_id = module.vpcs[each.value.vpc_key].id
  region = var.region

  acls = {
    for ak, av in lookup(each.value, "acls", {}) : ak => {
      default_policy = lookup(av, "default_policy", "accept")
      is_ipv6        = lookup(av, "is_ipv6", false)
      rules = [
        for r in lookup(av, "rules", []) : {
          protocol         = lookup(r, "protocol", "ANY")
          source_cidr      = lookup(r, "source_cidr", "0.0.0.0/0")
          destination_cidr = lookup(r, "destination_cidr", "0.0.0.0/0")
          action           = r.action
          description      = lookup(r, "description", null)
          src_port_low     = lookup(r, "src_port_low", null)
          src_port_high    = lookup(r, "src_port_high", null)
          dst_port_low     = lookup(r, "dst_port_low", null)
          dst_port_high    = lookup(r, "dst_port_high", null)
        }
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Public Gateways, NAT/egress + optional bastion
# ---------------------------------------------------------------------------

module "public_gateways" {
  source = "../../../modules/public-gateway"
  for_each = {

    for k, v in local.public_gateways : k => v
  }

  name       = "lz-${local.environment}-gw-${each.value.name}"
  project_id = local.project_id
  zone       = var.zone
  type       = lookup(each.value, "type", "VPC-GW-S")
  tags       = concat(local.common_tags, lookup(each.value, "tags", []))

  create_ip  = lookup(each.value, "create_ip", true)
  ip_id      = lookup(each.value, "ip_id", null)
  ip_reverse = lookup(each.value, "ip_reverse", null)

  bastion_enabled   = lookup(each.value, "bastion_enabled", false)
  bastion_port      = lookup(each.value, "bastion_port", 61000)
  allowed_ip_ranges = lookup(each.value, "allowed_ip_ranges", [])
  enable_smtp       = lookup(each.value, "enable_smtp", false)

  # gateway_networks from the gateway's vpc_key + private_network_keys
  gateway_networks = {
    for gn_key, gn_val in lookup(each.value, "gateway_networks", {}) : gn_key => {
      private_network_id = module.vpcs[gn_val.vpc_key].private_network_ids[gn_val.private_network_key]
      enable_masquerade  = lookup(gn_val, "enable_masquerade", true)
      push_default_route = lookup(gn_val, "push_default_route", true)
    }
  }
}

# ---------------------------------------------------------------------------
# DNS Zones & Records
# ---------------------------------------------------------------------------


module "dns" {
  source = "../../../modules/dns"

  count = length(local.dns_zones) > 0 ? 1 : 0

  project_id = local.project_id

  zones = {

    for k, v in local.dns_zones : k => {
      domain    = v.domain
      subdomain = v.subdomain
    }
  }

  records = {

    for k, v in local.dns_records : k => {
      zone_key = v.zone_key
      name     = v.name
      type     = v.type
      data     = v.data
      ttl      = lookup(v, "ttl", 3600)
      priority = lookup(v, "priority", 0)
    }
  }
}


# ---------------------------------------------------------------------------
# Remote State, Read security group IDs from Stage 1
# ---------------------------------------------------------------------------

data "terraform_remote_state" "stage1" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-1/terraform.tfstate"
    endpoints = {
      s3 = var.state_endpoint
    }
    access_key                  = var.state_access_key
    secret_key                  = var.state_secret_key
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

# ---------------------------------------------------------------------------
# Firewall Appliances, Instance VMs in Private Networks
# ---------------------------------------------------------------------------

module "firewall_appliances" {
  source = "../../../modules/instance-vm"
  for_each = {

    for k, v in local.firewall_appliances : k => v
  }

  name              = "lz-${local.environment}-${each.value.name}"
  instance_type     = each.value.instance_type
  image             = each.value.image
  project_id        = local.project_id
  zone              = lookup(each.value, "zone", var.zone)
  tags              = concat(local.common_tags, lookup(each.value, "tags", []))
  security_group_id = data.terraform_remote_state.stage1.outputs.security_group_ids[each.value.security_group_key]
  enable_dynamic_ip = lookup(each.value, "enable_dynamic_ip", false)
  state             = lookup(each.value, "state", "started")
  boot_type         = lookup(each.value, "boot_type", "local")
  protected         = lookup(each.value, "protected", false)

  root_volume = lookup(each.value, "root_volume", null)

  private_networks = {
    pn = {
      pn_id = module.vpcs[each.value.vpc_key].private_network_ids[each.value.private_network_key]
    }
  }

  user_data = lookup(each.value, "user_data", {})
}

# ---------------------------------------------------------------------------
# Load Balancers, Public-facing LBs with backends, frontends, ACLs
# ---------------------------------------------------------------------------

module "load_balancers" {
  source = "../../../modules/load-balancer"
  for_each = {
    for k, v in local.load_balancers : k => v
  }

  name       = "lz-${local.environment}-${each.value.name}"
  project_id = local.project_id
  zone       = lookup(each.value, "zone", var.zone)
  tags       = concat(local.common_tags, lookup(each.value, "tags", []))
  type       = lookup(each.value, "type", "LB-S")

  ips = lookup(each.value, "ip_reverse", null) != null ? {
    ipv4 = {
      reverse = each.value.ip_reverse
    }
  } : {}


  backends = {
    for bk, bv in lookup(each.value, "backends", {}) : bk => {
      name                         = lookup(bv, "name", bk)
      forward_protocol             = bv.forward_protocol
      forward_port                 = bv.forward_port
      forward_port_algorithm       = lookup(bv, "algorithm", "roundrobin")
      sticky_sessions              = lookup(bv, "sticky_sessions", "none")
      server_ips                   = length(lookup(bv, "server_ips", [])) > 0 ? lookup(bv, "server_ips", []) : (lookup(bv, "backend_instance_key", null) != null ? module.firewall_appliances[lookup(bv, "backend_instance_key", "dummy")].private_ips : [])
      proxy_protocol               = lookup(bv, "proxy_protocol", "none")
      timeout_server               = lookup(bv, "timeout_server", null)
      timeout_connect              = lookup(bv, "timeout_connect", null)
      timeout_tunnel               = lookup(bv, "timeout_tunnel", null)
      on_marked_down_action        = lookup(bv, "on_marked_down_action", "none")
      ignore_ssl_server_verify     = lookup(bv, "ignore_ssl_server_verify", false)
      redispatch_attempt_count     = lookup(bv, "redispatch_attempt_count", null)
      max_retries                  = lookup(bv, "max_retries", null)
      ssl_bridging                 = lookup(bv, "ssl_bridging", false)
      health_check_max_retries     = try(bv.health_check.check_max_retries, null)
      health_check_timeout         = try(bv.health_check.check_timeout, null)
      health_check_delay           = try(bv.health_check.check_delay, null)
      health_check_port            = try(bv.health_check.port, null)
      health_check_send_proxy      = try(bv.health_check.check_send_proxy, false)
      health_check_transient_delay = try(bv.health_check.transient_check_delay, null)
      health_check_tcp             = try(bv.health_check != null && bv.health_check.http_config == null ? true : false, false)
      health_check_http = try(bv.health_check.http_config != null ? {
        uri         = bv.health_check.http_config.uri
        method      = lookup(bv.health_check.http_config, "method", "GET")
        code        = lookup(bv.health_check.http_config, "code", "200")
        host_header = lookup(bv.health_check.http_config, "host", null)
      } : null, null)
    }
  }

  frontends = {
    for fk, fv in lookup(each.value, "frontends", {}) : fk => {
      name            = lookup(fv, "name", fk)
      backend_key     = fv.backend_key
      inbound_port    = fv.inbound_port
      timeout_client  = lookup(fv, "timeout_client", null)
      certificate_ids = lookup(fv, "enable_ssl", false) && lookup(fv, "ssl_certificate_id", null) != null ? [fv.ssl_certificate_id] : []
    }
  }

  acls = {
    for ak, av in lookup(each.value, "acls", {}) : ak => {
      name         = lookup(av, "name", ak)
      frontend_key = av.frontend_key
      index        = lookup(av, "index", 0)
      action       = av.action
      match = {
        ip_subnet          = try(av.match.ip_subnet, [])
        http_filter        = try(av.match.http_filter, null)
        http_filter_value  = try(av.match.http_filter_value, null)
        http_filter_option = try(av.match.http_filter_option, null)
      }
    }
  }
}
