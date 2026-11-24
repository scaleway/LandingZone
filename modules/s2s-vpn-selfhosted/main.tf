/**
 * Self-hosted Site-to-Site VPN Endpoint Module (strongSwan + BIRD2)
 *
 * Provision a compute instance as the on-prem "customer gateway" for
 * modules/s2s-vpn: strongSwan terminates the IPSec tunnel (mark/VTI-based),
 * BIRD2 peers BGP over it. PSK and remote endpoint are known up front
 * (Secret Manager / remote state), so cloud-init is fully declarative.
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

locals {
  name_prefix = "lz-${var.environment}"
  fw_mark     = 42
}

# ---------------------------------------------------------------------------
# Security group -- only the tunnel (UDP 500/4500) + SSH are reachable.
# ---------------------------------------------------------------------------
module "security_group" {
  source = "../security-group"

  name                    = "${local.name_prefix}-${var.name}-sg"
  project_id              = var.project_id
  zone                    = var.zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  enable_default_security = false
  tags                    = var.tags
  inbound_rules = concat(
    [
      # IKE / ESP-over-NAT from anywhere (the tunnel endpoint dials in).
      { action = "accept", protocol = "UDP", port = 500, ip_range = "0.0.0.0/0" },
      { action = "accept", protocol = "UDP", port = 4500, ip_range = "0.0.0.0/0" },
      # ICMP echo, for connectivity checks from the cloud side.
      { action = "accept", protocol = "ICMP", ip_range = "0.0.0.0/0" },
    ],
    [for cidr in var.ssh_cidrs : { action = "accept", protocol = "TCP", port = 22, ip_range = cidr }]
  )
}

# ---------------------------------------------------------------------------
# Instance -- the self-hosted VPN gateway, via the shared instance-vm module.
# An existing elastic IP (optional `public_ip_id`) is attached so the remote
# side always dials the same stable endpoint.
# ---------------------------------------------------------------------------
module "instance" {
  source = "../instance-vm"

  name              = "${local.name_prefix}-${var.name}"
  instance_type     = var.instance_type
  image             = var.image
  project_id        = var.project_id
  zone              = var.zone
  tags              = concat(var.tags, ["vpn", "selfhosted", "strongswan"])
  security_group_id = module.security_group.id
  create_instance   = var.create
  state             = var.state
  boot_type         = var.boot_type
  protected         = false

  existing_ip_ids = var.public_ip_id != null ? [var.public_ip_id] : []
  ips             = {}

  private_networks = {
    pn = {
      pn_id   = var.private_network_id
      ipam_ip = var.private_ip
    }
  }

  user_data = {
    "cloud-init" = templatefile("${path.module}/templates/strongswan-gateway.yaml.tftpl", {
      local_public_ip  = var.public_ip
      remote_public_ip = var.remote_public_ip
      local_tunnel_ip  = var.local_tunnel_ip  # e.g. 169.254.0.2/30 (this side)
      local_bgp_ip     = var.local_bgp_ip     # e.g. 169.254.0.2  (bare, for BIRD)
      remote_tunnel_ip = var.remote_tunnel_ip # e.g. 169.254.0.1  (peer BGP IP)
      local_asn        = var.local_asn
      remote_asn       = var.remote_asn # Scaleway side (typically 12876)
      psk              = var.psk
      ike_ciphers      = var.ike_ciphers
      esp_ciphers      = var.esp_ciphers
      vti_mark         = local.fw_mark
      advertise_cidrs  = var.advertise_cidrs  # routes advertised to the peer
      learn_cidrs      = var.learn_cidrs      # routes expected from the peer
      tunnel_interface = var.tunnel_interface # e.g. vti0
      router_id        = var.router_id
      ssh_keys         = var.ssh_keys # operator keys (cloud-init users block)
    })
  }
}

output "id" {
  description = "ID of the self-hosted VPN gateway instance."
  value       = module.instance.id
}

output "name" {
  description = "Name of the self-hosted VPN gateway instance."
  value       = module.instance.name
}

output "private_ips" {
  description = "Private IPs of the gateway on the attached private network."
  value       = module.instance.private_ips
}

output "private_ips_map" {
  description = "Private IPs keyed by private-network key."
  value       = module.instance.private_ips_map
}

output "public_ip_id" {
  description = "ID of the elastic public IP attached to the gateway."
  value       = var.public_ip_id
}

output "private_nic_ids" {
  description = "Map of private-NIC IDs (keyed by private-network key) for VPC route next hops."
  value       = module.instance.private_nic_ids
}
