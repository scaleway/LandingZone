/**
 * Stage 1, Security
 * IAM policies, Cockpit observability, KMS keys, Secret Manager secrets,
 * and security groups. Reads bootstrap state for org/project IDs.
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
    key = "stage-1/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Remote State, Read org/project info from bootstrap
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
  stage_id    = "stage1"
}

locals {
  project_id  = data.terraform_remote_state.bootstrap.outputs.project_ids[var.project_key]
  environment = data.terraform_remote_state.bootstrap.outputs.environment

  common_tags = module.common_tags.list

  # YAML factory: per-env data (envs/<env>/data/security-<env>.yaml, -demo
  # preferred when present); tfvars overrides win.
  factory_file = fileexists("${path.module}/../../envs/${local.environment}/data/security-${local.environment}-demo.yaml") ? "${path.module}/../../envs/${local.environment}/data/security-${local.environment}-demo.yaml" : "${path.module}/../../envs/${local.environment}/data/security-${local.environment}.yaml"

  factory_raw = yamldecode(file(local.factory_file))

  cockpit  = merge(local.factory_raw.cockpit, var.cockpit)
  kms_keys = merge(local.factory_raw.kms_keys, var.kms_keys)


  secrets         = merge(local.factory_raw.secrets, var.secrets)
  security_groups = merge(local.factory_raw.security_groups, var.security_groups)

  # SGs are zone-scoped: mirror every SG into AZ1 (where fw-passive lives).
  # Empty/absent = no AZ1 duplicates.
  security_groups_az1_zone = try(local.factory_raw.security_groups_az1_zone, var.security_groups_az1_zone, "")
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = local.project_id
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# Cockpit (Observability)
# ---------------------------------------------------------------------------

module "cockpit" {
  source   = "../../../modules/logs"
  for_each = { for k, v in local.cockpit : k => v }

  project_id = local.project_id
  region     = var.region
  sources    = lookup(each.value, "sources", {})
  tokens     = lookup(each.value, "tokens", {})
}

# ---------------------------------------------------------------------------
# KMS Keys
# ---------------------------------------------------------------------------

module "kms_keys" {
  source   = "../../../modules/kms"
  for_each = { for k, v in local.kms_keys : k => v }


  name        = "lz-${local.environment}-${each.value.name}"
  project_id  = local.project_id
  region      = var.region
  description = lookup(each.value, "description", null)
  unprotected = lookup(each.value, "unprotected", false)
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

module "secrets" {
  source   = "../../../modules/secrets"
  for_each = { for k, v in local.secrets : k => v }


  name        = "lz-${local.environment}-${each.value.name}"
  project_id  = local.project_id
  region      = var.region
  description = lookup(each.value, "description", null)
  tags        = concat(local.common_tags, lookup(each.value, "tags", []))
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

module "security_groups" {
  source   = "../../../modules/security-group"
  for_each = { for k, v in local.security_groups : k => v }


  name                    = "lz-${local.environment}-${each.value.name}"
  project_id              = local.project_id
  zone                    = var.zone
  description             = lookup(each.value, "description", null)
  stateful                = lookup(each.value, "stateful", true)
  inbound_default_policy  = lookup(each.value, "inbound_default_policy", "drop")
  outbound_default_policy = lookup(each.value, "outbound_default_policy", "accept")
  enable_default_security = lookup(each.value, "enable_default_security", true)
  tags                    = concat(local.common_tags, lookup(each.value, "tags", []))
  inbound_rules           = lookup(each.value, "inbound_rules", [])
  outbound_rules          = lookup(each.value, "outbound_rules", [])
}

module "security_groups_az1" {
  source   = "../../../modules/security-group"
  for_each = { for k, v in local.security_groups : k => v if local.security_groups_az1_zone != "" }


  name                    = "lz-${local.environment}-${each.value.name}"
  project_id              = local.project_id
  zone                    = local.security_groups_az1_zone
  description             = lookup(each.value, "description", null)
  stateful                = lookup(each.value, "stateful", true)
  inbound_default_policy  = lookup(each.value, "inbound_default_policy", "drop")
  outbound_default_policy = lookup(each.value, "outbound_default_policy", "accept")
  enable_default_security = lookup(each.value, "enable_default_security", true)
  tags                    = concat(local.common_tags, lookup(each.value, "tags", []))
  inbound_rules           = lookup(each.value, "inbound_rules", [])
  outbound_rules          = lookup(each.value, "outbound_rules", [])
}
