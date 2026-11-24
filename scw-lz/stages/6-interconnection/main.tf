/**
 * Stage 6, Interconnection
 * Hybrid edge connectivity: managed Site-to-Site VPN on the hub PN (PSK
 * auto-generated in Secret Manager) plus an emulated on-premises lab
 * (strongSwan + BIRD2) as a validation harness. The lab gateway is created
 * last so cloud-init carries the PSK + pinned VGW public IP, no post-apply
 * step.
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    key = "stage-6/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Remote State, bootstrap (projects/environment) + Stage 2 (hub VPC/PN)
# ---------------------------------------------------------------------------

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    # bootstrap's local state path (written into remote_state-<env>.tfvars).
    path = var.stage0_state_path
  }
}

data "terraform_remote_state" "stage2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-2/terraform.tfstate"
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

  # Always-read anchor (its outputs don't feed back into lab_wiring_ok, so no
  # cycle) that fails loudly, instead of an opaque "Invalid index", when the
  # lab flags disagree. See lab_wiring_ok.
  lifecycle {
    precondition {
      condition = local.lab_wiring_ok
      error_message = format(
        "Mismatched on-premises lab wiring: onprem_lab.enabled=%t but %d s2s_vpn_connections entrie(s) set onprem_lab_peer: true. The emulated gateway needs exactly one lab-peer connection, and only while the lab is enabled.",
        local.onprem.enabled, local.lab_peer_count,
      )
    }
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
  stage_id    = "stage6"
}

locals {
  project_id  = data.terraform_remote_state.bootstrap.outputs.project_ids[var.project_key]
  environment = data.terraform_remote_state.bootstrap.outputs.environment

  common_tags = module.common_tags.list

  # YAML factory, reuses Stage 2's networking-<env>.yaml (s2s_vpn_connections
  # + onprem_lab sections), -demo preferred when present.
  factory_file = fileexists("${path.module}/../../envs/${local.environment}/data/networking-${local.environment}-demo.yaml") ? "${path.module}/../../envs/${local.environment}/data/networking-${local.environment}-demo.yaml" : "${path.module}/../../envs/${local.environment}/data/networking-${local.environment}.yaml"

  factory_raw = yamldecode(file(local.factory_file))

  # S2S VPN connections: factory merged with optional tfvars override.
  s2s_vpn_connections = merge(try(local.factory_raw.s2s_vpn_connections, {}), var.s2s_vpn_connections)

  # Emulated on-premises site (all gates driven by the factory).
  onprem = {
    enabled         = try(local.factory_raw.onprem_lab.enabled, false)
    vpc             = try(local.factory_raw.onprem_lab.vpc, {})
    gateway         = try(local.factory_raw.onprem_lab.gateway, {})
    cloud_cidrs     = try(local.factory_raw.onprem_lab.cloud_cidrs, [])
    cloud_ssh_cidrs = try(local.factory_raw.onprem_lab.cloud_ssh_cidrs, [])
    vms             = try(local.factory_raw.onprem_lab.vms, {})
  }

  # The managed connection that terminates on the emulated gateway (exactly one).
  lab_conn_key = try([for k, v in local.s2s_vpn_connections : k if lookup(v, "onprem_lab_peer", false)][0], "")

  # Lab is active only when enabled AND a lab-terminated connection is defined.
  lab_active = local.onprem.enabled && local.lab_conn_key != ""

  # Count of onprem_lab_peer tags (harness supports exactly one, only while enabled).
  lab_peer_count = length([for k, v in local.s2s_vpn_connections : v if lookup(v, "onprem_lab_peer", false)])

  # Lab toggle <=> lab-peer consistency; named local so the s2s_vpn precondition
  # fails loudly instead of with an opaque "Invalid index".
  lab_wiring_ok = (local.onprem.enabled && local.lab_peer_count == 1) || (!local.onprem.enabled && local.lab_peer_count == 0)

  # Bracket index on purpose: a missing key errors, so try() can fall back to
  # the first PN (dot access returns null and silently skips the fallback).
  onprem_pn_key = try(local.onprem.gateway["private_network_key"], keys(local.onprem.vpc.private_networks)[0])
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = local.project_id
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# Managed Site-to-Site VPN, a lab-peer connection resolves its customer
# endpoint + pinned VGW public IP from the emulated lab below.
# ---------------------------------------------------------------------------

module "s2s_vpn" {
  source = "../../../modules/s2s-vpn"

  count = length(local.s2s_vpn_connections) > 0 ? 1 : 0

  region      = var.region
  zone        = var.zone
  project_id  = local.project_id
  environment = local.environment

  vpn_connections = {
    for k, v in local.s2s_vpn_connections : k => merge(
      {
        gateway_name          = lookup(v, "gateway_name", "lz-${local.environment}-vpn-gw-${k}")
        customer_gateway_name = lookup(v, "customer_gateway_name", "lz-${local.environment}-vpn-cgw-${k}")
        routing_policy_name   = lookup(v, "routing_policy_name", "lz-${local.environment}-vpn-policy-${k}")
        connection_name       = lookup(v, "connection_name", "lz-${local.environment}-vpn-conn-${k}")

        gateway_type       = lookup(v, "gateway_type", "VGW-S")
        private_network_id = data.terraform_remote_state.stage2.outputs.private_network_ids[lookup(v, "vpc_key", "")][lookup(v, "private_network_key", "")]
        ipam_ipv4_id       = lookup(v, "ipam_ipv4_id", null)
        ipam_ipv6_id       = lookup(v, "ipam_ipv6_id", null)

        customer_ipv4_public = lookup(v, "customer_ipv4_public", null)
        customer_ipv6_public = lookup(v, "customer_ipv6_public", null)
        customer_asn         = lookup(v, "customer_asn", null)

        prefix_filter_in  = lookup(v, "prefix_filter_in", [])
        prefix_filter_out = lookup(v, "prefix_filter_out", [])

        initiation_policy        = lookup(v, "initiation_policy", "customer_gateway")
        enable_route_propagation = lookup(v, "enable_route_propagation", true)
        is_ipv6                  = lookup(v, "is_ipv6", false)

        psk = lookup(v, "psk", null)

        bgp_private_ip      = lookup(v, "bgp_private_ip", null)
        bgp_peer_private_ip = lookup(v, "bgp_peer_private_ip", null)

        ikev2_encryption = lookup(v, "ikev2_encryption", null)
        ikev2_integrity  = lookup(v, "ikev2_integrity", null)
        ikev2_dh_group   = lookup(v, "ikev2_dh_group", null)
        esp_encryption   = lookup(v, "esp_encryption", null)
        esp_integrity    = lookup(v, "esp_integrity", null)
        esp_dh_group     = lookup(v, "esp_dh_group", null)

        tags = concat(local.common_tags, lookup(v, "tags", []))
      },
      # Lab-terminated connection: resolve the endpoint from the lab resources.
      lookup(v, "onprem_lab_peer", false) ? {
        customer_ipv4_public = scaleway_instance_ip.onprem_pub[0].address
        ipam_ipv4_id         = scaleway_ipam_ip.vgw_public[0].id
      } : {}
    )
  }
}

# ---------------------------------------------------------------------------
# Emulated on-premises site (active when `onprem_lab.enabled` + a lab peer)
# ---------------------------------------------------------------------------

# On-prem gateway's elastic public IP, the "customer gateway" the VGW dials.
resource "scaleway_instance_ip" "onprem_pub" {
  count      = local.lab_active ? 1 : 0
  zone       = var.zone
  project_id = local.project_id
  tags       = concat(local.common_tags, ["onprem", "vpn", "customer-gateway"])
}

# Pinned VGW public IP (zonal IPAM reservation): what strongSwan dials and
# puts on its VTI interface.
resource "scaleway_ipam_ip" "vgw_public" {
  count      = local.lab_active ? 1 : 0
  is_ipv6    = false
  project_id = local.project_id
  source {
    zonal = var.zone
  }
}

# PSK resolved after the connection exists, so the on-prem gateway can boot
# with the correct secret.
data "scaleway_secret_version" "psk" {
  count     = local.lab_active ? 1 : 0
  secret_id = module.s2s_vpn[0].secret_ids[local.lab_conn_key]
  revision  = tostring(module.s2s_vpn[0].secret_versions[local.lab_conn_key])
}

# On-premises lab VPC, a separate, isolated "site" with its own LAN.
module "onprem_vpc" {
  source = "../../../modules/vpc"

  count = local.onprem.enabled ? 1 : 0

  name                             = "lz-${local.environment}-vpc-${local.onprem.vpc.name}"
  project_id                       = local.project_id
  region                           = var.region
  tags                             = concat(local.common_tags, try(local.onprem.vpc.tags, ["onprem", "tunnel"]))
  enable_routing                   = lookup(local.onprem.vpc, "enable_routing", true)
  enable_custom_routes_propagation = lookup(local.onprem.vpc, "enable_custom_routes_propagation", true)
  enable_transitivity              = lookup(local.onprem.vpc, "enable_transitivity", false)

  private_networks = {
    for pk, pv in local.onprem.vpc.private_networks : pk => {
      name              = pv.name
      ipv4_subnet_cidr  = lookup(pv, "ipv4_subnet_cidr", null)
      ipv6_subnet_cidrs = lookup(pv, "ipv6_subnet_cidrs", [])
      tags              = concat(local.common_tags, lookup(pv, "tags", []))
    }
  }
}

# Self-hosted on-prem gateway: strongSwan + BIRD2 (customer gateway role).
module "onprem_gateway" {
  source = "../../../modules/s2s-vpn-selfhosted"

  count = local.lab_active ? 1 : 0

  name          = try(local.onprem.gateway.name, "onprem-gw")
  environment   = local.environment
  project_id    = local.project_id
  zone          = var.zone
  instance_type = lookup(local.onprem.gateway, "instance_type", "PLAY2-MICRO")
  image         = lookup(local.onprem.gateway, "image", "ubuntu_jammy")
  tags          = concat(local.common_tags, try(local.onprem.gateway.tags, ["onprem", "tunnel"]))

  private_network_id = module.onprem_vpc[0].private_network_ids[local.onprem_pn_key]
  private_ip         = local.onprem.gateway.private_ip

  public_ip_id = scaleway_instance_ip.onprem_pub[0].id
  public_ip    = scaleway_instance_ip.onprem_pub[0].address

  remote_public_ip = scaleway_ipam_ip.vgw_public[0].address

  local_tunnel_ip  = local.onprem.gateway.local_tunnel_ip  # 169.254.0.2/30
  local_bgp_ip     = local.onprem.gateway.local_bgp_ip     # 169.254.0.2
  remote_tunnel_ip = local.onprem.gateway.remote_tunnel_ip # 169.254.0.1
  local_asn        = local.onprem.gateway.asn
  remote_asn       = module.s2s_vpn[0].vpn_gateway_asns[local.lab_conn_key]
  psk              = base64decode(data.scaleway_secret_version.psk[0].data)

  # Advertise every lab subnet over BGP (not just the gateway's own PN) so any
  # lab workload stays reachable from the hub.
  advertise_cidrs = [for pk, pv in local.onprem.vpc.private_networks : pv.ipv4_subnet_cidr]
  learn_cidrs     = local.onprem.cloud_cidrs

  router_id = local.onprem.gateway.private_ip
  ssh_cidrs = try(local.onprem.gateway.ssh_cidrs, [])
  # Operator access: the org admin_key (same one that admins the stage-3 FWs).
  ssh_keys = concat(
    [trimspace(data.terraform_remote_state.bootstrap.outputs.ssh_public_keys["admin_key"])],
    try(local.onprem.gateway.ssh_keys, []),
  )
}

# Security group for the lab workload VM (SSH + ICMP only).
module "onprem_vm_sg" {
  source = "../../../modules/security-group"

  count = local.onprem.enabled ? 1 : 0

  name                    = "lz-${local.environment}-onprem-vm-sg"
  project_id              = local.project_id
  zone                    = var.zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  enable_default_security = false
  tags                    = concat(local.common_tags, ["onprem", "tunnel"])
  inbound_rules = concat(
    [{ action = "accept", protocol = "ICMP", ip_range = "0.0.0.0/0" }],
    # SSH: operator egress (gateway.ssh_cidrs) plus any hub/test CIDRs the lab
    # story allows through the tunnel (cloud_ssh_cidrs, e.g. the hub-test agent).
    [
      for cidr in distinct(concat(try(local.onprem.gateway.ssh_cidrs, []), try(local.onprem.cloud_ssh_cidrs, []))) :
      { action = "accept", protocol = "TCP", port = 22, ip_range = cidr }
    ]
  )
}

# Lab workload VM proving cross-tunnel connectivity. Gated on lab_active,
# the VM is only useful once the tunnel exists to reach it through.
module "onprem_vms" {
  source = "../../../modules/instance-vm"

  for_each = local.lab_active ? local.onprem.vms : {}

  name              = "lz-${local.environment}-${each.key}"
  instance_type     = lookup(each.value, "instance_type", "PLAY2-MICRO")
  image             = lookup(each.value, "image", "ubuntu_jammy")
  project_id        = local.project_id
  zone              = var.zone
  tags              = concat(local.common_tags, lookup(each.value, "tags", ["onprem"]))
  security_group_id = module.onprem_vm_sg[0].id
  enable_dynamic_ip = lookup(each.value, "enable_dynamic_ip", false)

  private_networks = {
    pn = {
      pn_id   = module.onprem_vpc[0].private_network_ids[local.onprem_pn_key]
      ipam_ip = lookup(each.value, "private_ip", null)
    }
  }

  # No PGW, and DHCP advertises cloud routes only to the gateway NIC, so inject
  # the same routes into each VM, it can't reach (or answer) the hub over the
  # tunnel without them. Replaces any YAML-provided cloud-init.
  user_data = merge(
    try(each.value.user_data, {}),
    {
      "cloud-init" = templatefile("${path.module}/templates/onprem-vm.yaml.tftpl", {
        gateway_ip    = module.onprem_gateway[0].private_ips_map["pn"]
        cloud_cidrs   = local.onprem.cloud_cidrs
        operator_keys = [trimspace(data.terraform_remote_state.bootstrap.outputs.ssh_public_keys["admin_key"])]
      })
    }
  )
}

# Static routes in the on-prem VPC sending cloud CIDRs through the gateway
# (BGP converges the return path; these cover the forward path pre-BGP).
module "onprem_routes" {
  source = "../../../modules/vpc-route"

  for_each = local.lab_active ? { for c in local.onprem.cloud_cidrs : c => c } : {}

  vpc_id = module.onprem_vpc[0].id
  region = var.region

  routes = {
    to-cloud = {
      destination                = each.value
      nexthop_private_network_id = module.onprem_vpc[0].private_network_ids[local.onprem_pn_key]
      tags                       = concat(local.common_tags, ["onprem", "tunnel"])
    }
  }
}
