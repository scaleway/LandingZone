/**
 * Scaleway Site-to-Site VPN Module
 *
 * Creates S2S VPN connections: gateway + customer gateway + routing policy +
 * connection. The PSK is terraform-owned via Secret Manager, the API's
 * auto-generated secret is PROTECTED and survives destroy, ours is removed
 * together with the connection.
 */
terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# ---------------------------------------------------------------------------
# VPN Gateways, Scaleway-side, attached to a Private Network
# ---------------------------------------------------------------------------

resource "scaleway_s2s_vpn_gateway" "this" {
  for_each = var.vpn_connections

  name               = coalesce(each.value.gateway_name, "lz-${var.environment}-networking-vpn-gw-${each.key}")
  gateway_type       = coalesce(each.value.gateway_type, "VGW-S")
  private_network_id = each.value.private_network_id
  tags               = coalesce(each.value.tags, [])
  region             = var.region
  zone               = var.zone
  project_id         = var.project_id

  dynamic "public_config" {
    for_each = each.value.ipam_ipv4_id != null || each.value.ipam_ipv6_id != null ? [1] : []
    content {
      ipam_ipv4_id = each.value.ipam_ipv4_id
      ipam_ipv6_id = each.value.ipam_ipv6_id
    }
  }
}

# ---------------------------------------------------------------------------
# Customer Gateways, Remote endpoint (on-prem router/firewall)
# ---------------------------------------------------------------------------

resource "scaleway_s2s_vpn_customer_gateway" "this" {
  for_each = var.vpn_connections

  name        = coalesce(each.value.customer_gateway_name, "lz-${var.environment}-networking-vpn-cgw-${each.key}")
  ipv4_public = each.value.customer_ipv4_public
  ipv6_public = lookup(each.value, "customer_ipv6_public", null)
  asn         = each.value.customer_asn
  tags        = lookup(each.value, "tags", [])
  region      = var.region
  project_id  = var.project_id
}

# ---------------------------------------------------------------------------
# Routing Policies, BGP prefix filtering
# ---------------------------------------------------------------------------

resource "scaleway_s2s_vpn_routing_policy" "ipv4" {
  for_each = {
    for k, v in var.vpn_connections : k => v
    if lookup(v, "is_ipv6", false) == false
  }

  name              = coalesce(each.value.routing_policy_name, "lz-${var.environment}-networking-vpn-policy-ipv4-${each.key}")
  prefix_filter_in  = lookup(each.value, "prefix_filter_in", [])
  prefix_filter_out = lookup(each.value, "prefix_filter_out", [])
  is_ipv6           = false
  tags              = lookup(each.value, "tags", [])
  region            = var.region
  project_id        = var.project_id
}

resource "scaleway_s2s_vpn_routing_policy" "ipv6" {
  for_each = {
    for k, v in var.vpn_connections : k => v
    if lookup(v, "is_ipv6", false) == true
  }

  name              = coalesce(each.value.routing_policy_name, "lz-${var.environment}-networking-vpn-policy-ipv6-${each.key}")
  prefix_filter_in  = lookup(each.value, "prefix_filter_in", [])
  prefix_filter_out = lookup(each.value, "prefix_filter_out", [])
  is_ipv6           = true
  tags              = lookup(each.value, "tags", [])
  region            = var.region
  project_id        = var.project_id
}

# ---------------------------------------------------------------------------
# VPN Connections, Links gateway + customer gateway with BGP + IPSec
# ---------------------------------------------------------------------------

resource "scaleway_s2s_vpn_connection" "this" {
  for_each = var.vpn_connections

  name                     = coalesce(each.value.connection_name, "lz-${var.environment}-networking-vpn-conn-${each.key}")
  vpn_gateway_id           = scaleway_s2s_vpn_gateway.this[each.key].id
  customer_gateway_id      = scaleway_s2s_vpn_customer_gateway.this[each.key].id
  initiation_policy        = lookup(each.value, "initiation_policy", "customer_gateway")
  enable_route_propagation = lookup(each.value, "enable_route_propagation", true)
  secret_id                = scaleway_secret.psk[each.key].id
  secret_version           = scaleway_secret_version.psk[each.key].revision
  is_ipv6                  = lookup(each.value, "is_ipv6", false)
  tags                     = lookup(each.value, "tags", [])
  region                   = var.region
  project_id               = var.project_id

  dynamic "bgp_config_ipv4" {
    for_each = lookup(each.value, "is_ipv6", false) == false ? [1] : []
    content {
      routing_policy_id = scaleway_s2s_vpn_routing_policy.ipv4[each.key].id
      private_ip        = lookup(each.value, "bgp_private_ip", null)
      peer_private_ip   = lookup(each.value, "bgp_peer_private_ip", null)
    }
  }

  dynamic "bgp_config_ipv6" {
    for_each = lookup(each.value, "is_ipv6", false) == true ? [1] : []
    content {
      routing_policy_id = scaleway_s2s_vpn_routing_policy.ipv6[each.key].id
      private_ip        = lookup(each.value, "bgp_private_ip", null)
      peer_private_ip   = lookup(each.value, "bgp_peer_private_ip", null)
    }
  }

  dynamic "ikev2_ciphers" {
    for_each = lookup(each.value, "ikev2_encryption", null) != null ? [1] : []
    content {
      encryption = each.value.ikev2_encryption
      integrity  = lookup(each.value, "ikev2_integrity", "sha256")
      dh_group   = lookup(each.value, "ikev2_dh_group", "modp2048")
    }
  }

  dynamic "esp_ciphers" {
    for_each = lookup(each.value, "esp_encryption", null) != null ? [1] : []
    content {
      encryption = each.value.esp_encryption
      integrity  = lookup(each.value, "esp_integrity", "sha256")
      dh_group   = lookup(each.value, "esp_dh_group", "modp2048")
    }
  }
}

# ---------------------------------------------------------------------------
# PSK secrets, terraform-owned, so destroy removes them with the connection
# ---------------------------------------------------------------------------
# scaleway_s2s_vpn_connection takes no `psk`: when secret_id is omitted the API
# auto-generates a PROTECTED secret that survives destroy (dead leftover on
# every re-create). We own it instead.

# Optional per-connection PSK override; a random value is generated when unset.
resource "random_password" "psk" {
  for_each = { for k, v in var.vpn_connections : k => v if v.psk == null }

  length  = 48
  special = false
}

locals {
  psk_values = {
    for k, v in var.vpn_connections : k => (v.psk != null ? v.psk : random_password.psk[k].result)
  }
}

resource "scaleway_secret" "psk" {
  for_each = var.vpn_connections

  name       = "lz-${var.environment}-vpn-psk-${each.key}"
  project_id = var.project_id
  region     = var.region
  tags       = concat(lookup(each.value, "tags", []), ["s2s-vpn", "psk"])
}

resource "scaleway_secret_version" "psk" {
  for_each = var.vpn_connections

  secret_id = scaleway_secret.psk[each.key].id
  data      = local.psk_values[each.key]
  region    = var.region
}