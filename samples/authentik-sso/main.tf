/**
 * Sample: self-hosted Authentik IdP for console SSO (SAML/SCIM).
 *
 * Single-node Authentik (official docker-compose: server + worker + embedded
 * PostgreSQL/Redis) on a Scaleway instance, exposed over 80/443. Outputs
 * idp_entity_id/idp_sso_url for bootstrap's `sso:` block; the signing cert
 * is downloaded from the Authentik UI, SCIM is optional.
 */

terraform {
  required_version = ">= 1.5"
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = var.project_id
  region          = var.region
  zone            = var.zone
}

locals {
  # Same tag convention as the scw-lz stages.
  common_tags = [
    "managed-by=landing-zone-toolkit",
    "env=${var.environment}",
    "stage=sso",
  ]
}

# ---------------------------------------------------------------------------
# Generated secrets (one-shot: kept in state for this sample - see README)
# ---------------------------------------------------------------------------
resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "random_password" "postgres_password" {
  length  = 24
  special = false
}

resource "random_password" "bootstrap_token" {
  length  = 48
  special = false
}

# ---------------------------------------------------------------------------
# Rendered artifacts
# ---------------------------------------------------------------------------
locals {
  idp_entity_id = "https://${var.authentik_fqdn}/application/o/${var.application_slug}/"
  idp_sso_url   = local.idp_entity_id

  compose = templatefile("${path.module}/files/docker-compose.yml.tftpl", {
    image_tag         = var.authentik_image_tag
    secret_key        = random_password.secret_key.result
    postgres_password = random_password.postgres_password.result
    bootstrap_token   = random_password.bootstrap_token.result
    fqdn              = var.authentik_fqdn
    bootstrap_email   = var.bootstrap_email
  })

  cloud_init = templatefile("${path.module}/files/cloud-init.yml.tftpl", {
    compose_b64 = base64encode(local.compose)
  })

  inbound_rules = concat(
    [for c in var.allowed_cidrs : { action = "accept", protocol = "TCP", port = 443, ip_range = c }],
    [for c in var.allowed_cidrs : { action = "accept", protocol = "TCP", port = 80, ip_range = c }],
    [for c in var.ssh_cidrs : { action = "accept", protocol = "TCP", port = 22, ip_range = c }],
  )
}

# ---------------------------------------------------------------------------
# Security group: 443/80 for the IdP, 22 for admin (restrict via vars)
# ---------------------------------------------------------------------------
module "sg" {
  source = "../../modules/security-group"

  name                    = var.name_prefix
  description             = "Authentik IdP: HTTPS/HTTP + SSH"
  project_id              = var.project_id
  zone                    = var.zone
  stateful                = true
  inbound_default_policy  = "drop"
  outbound_default_policy = "accept"
  enable_default_security = true
  inbound_rules           = local.inbound_rules
  tags                    = local.common_tags
}

# ---------------------------------------------------------------------------
# The Authentik instance: Docker compose via cloud-init, flexible public IP
# ---------------------------------------------------------------------------
module "authentik" {
  source = "../../modules/instance-vm"

  name              = var.name_prefix
  instance_type     = var.instance_type
  image             = var.image
  project_id        = var.project_id
  zone              = var.zone
  tags              = concat(local.common_tags, ["sso", "authentik", "idp"])
  security_group_id = module.sg.id
  create_instance   = true

  ips = var.enable_public_ip ? {
    ipv4 = { reverse = var.authentik_fqdn }
  } : {}

  root_volume = {
    size_in_gb            = var.root_volume_size_gb
    volume_type           = "sbs_volume"
    delete_on_termination = true
  }

  user_data = {
    "cloud-init" = local.cloud_init
  }
}
