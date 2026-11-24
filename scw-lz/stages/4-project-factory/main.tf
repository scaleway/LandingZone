/**
 * Stage 4, Project Factory
 * Application/team projects wired to the hub (VPC peering), with IAM groups,
 * service accounts, policies, and optional object storage buckets.
 * Reads bootstrap (org/projects) + Stage 2 (networking) state.
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
    key = "stage-4/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Remote State, Read org/project info from bootstrap and networking from Stage 2
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
}

# ---------------------------------------------------------------------------
# Common tags: the org's tag policy (var.common_tags) plus the toolkit-
# reserved markers managed-by / env / stage. Composition is the single
# source of truth in modules/tags; local.common_tags / common_tags_map below
# just alias the module outputs so the rest of this file keeps using
# local.common_tags.
# ---------------------------------------------------------------------------
module "common_tags" {
  source      = "../../../modules/tags"
  user_tags   = var.common_tags
  environment = local.environment
  stage_id    = "stage4"
}

locals {
  # Hub VPC from stage 2; "" fallback keeps a stage-4 destroy working against
  # torn-down state (same guard as stage 5).
  hub_vpc_id = try(data.terraform_remote_state.stage2.outputs.vpc_ids["hub"], "")

  # Environment from bootstrap (single source of truth)
  environment = data.terraform_remote_state.bootstrap.outputs.environment

  common_tags     = module.common_tags.list
  common_tags_map = module.common_tags.map

  # YAML factory: per-env data (envs/<env>/data/projects-<env>.yaml, -demo
  # preferred when present); tfvars overrides win.
  factory_file = fileexists("${path.module}/../../envs/${local.environment}/data/projects-${local.environment}-demo.yaml") ? "${path.module}/../../envs/${local.environment}/data/projects-${local.environment}-demo.yaml" : "${path.module}/../../envs/${local.environment}/data/projects-${local.environment}.yaml"

  factory_raw = yamldecode(file(local.factory_file))

  projects         = merge(local.factory_raw.projects, var.projects)
  service_accounts = merge(local.factory_raw.service_accounts, var.service_accounts)
  iam_groups       = merge(local.factory_raw.iam_groups, var.iam_groups)
  iam_policies     = merge(local.factory_raw.iam_policies, var.iam_policies)
  vpc_peerings     = merge(local.factory_raw.vpc_peerings, var.vpc_peerings)
  object_buckets   = merge(try(local.factory_raw.object_buckets, {}), var.object_buckets)

  # Resolve principal keys into module IDs before handing to the iam-policy module.
  iam_policies_resolved = {
    for k, v in local.iam_policies : k => {
      name            = "lz-${local.environment}-${lookup(v, "name", k)}"
      description     = lookup(v, "description", null)
      tags            = concat(local.common_tags, lookup(v, "tags", []))
      organization_id = var.organization_id
      user_id         = lookup(v, "user_id", null)
      group_id        = lookup(v, "group_id", null) != null ? module.iam_groups[lookup(v, "group_id", null)].id : null
      application_id  = lookup(v, "application_id", null) != null ? module.service_accounts[lookup(v, "application_id", null)].id : null
      no_principal    = lookup(v, "no_principal", false)
      rules           = lookup(v, "rules", [])
    }
  }
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = data.terraform_remote_state.bootstrap.outputs.project_ids[var.parent_project_key]
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# Projects, Application/team-level projects
# ---------------------------------------------------------------------------

module "projects" {
  source   = "../../../modules/project"
  for_each = { for k, v in local.projects : k => v }

  name            = "lz-${local.environment}-${each.value.name}"
  description     = lookup(each.value, "description", null)
  organization_id = var.organization_id
  project_id      = lookup(each.value, "project_id", null)
  tags            = concat(local.common_tags, lookup(each.value, "tags", []))
}

# ---------------------------------------------------------------------------
# Factory VPCs, Create a VPC in each factory project for peering
# ---------------------------------------------------------------------------

module "factory_vpcs" {
  source   = "../../../modules/vpc"
  for_each = { for k, v in local.projects : k => v }

  name                             = "lz-${local.environment}-vpc-${lookup(each.value, "vpc", {}) != {} ? lookup(each.value, "vpc", {}).name : each.value.name}"
  project_id                       = module.projects[each.key].id
  region                           = var.region
  tags                             = concat(local.common_tags, [])
  enable_routing                   = true
  enable_custom_routes_propagation = true
  enable_transitivity              = false

  private_networks = {
    for pn_key, pn_val in lookup(lookup(each.value, "vpc", {}), "private_networks", {}) : pn_key => {
      name             = pn_val.name
      ipv4_subnet_cidr = pn_val.ipv4_subnet_cidr
      tags             = concat(local.common_tags, [])
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Groups, Per-project groups
# ---------------------------------------------------------------------------

module "iam_groups" {
  source   = "../../../modules/iam-group"
  for_each = { for k, v in local.iam_groups : k => v }

  name            = "lz-${local.environment}-${each.value.name}"
  description     = lookup(each.value, "description", null)
  tags            = concat(local.common_tags, lookup(each.value, "tags", []))
  application_ids = [for app_key in lookup(each.value, "application_ids", []) : module.service_accounts[app_key].id]
  user_ids        = lookup(each.value, "user_ids", [])
  organization_id = var.organization_id
}

# ---------------------------------------------------------------------------
# IAM Service Accounts, Per-project service accounts
# ---------------------------------------------------------------------------

module "service_accounts" {
  source   = "../../../modules/iam-service-account"
  for_each = { for k, v in local.service_accounts : k => v }

  name                       = "lz-${local.environment}-${each.value.name}"
  description                = lookup(each.value, "description", null)
  tags                       = concat(local.common_tags, lookup(each.value, "tags", []))
  organization_id            = var.organization_id
  create_api_key             = lookup(each.value, "create_api_key", true)
  api_key_description        = lookup(each.value, "api_key_description", "API key for service account")
  api_key_expires_at         = lookup(each.value, "api_key_expires_at", null)
  api_key_default_project_id = lookup(each.value, "project_key", null) != null ? module.projects[each.value.project_key].id : null
}

# ---------------------------------------------------------------------------
# IAM Policies, Permission sets scoped to factory projects (factory-style map)
# ---------------------------------------------------------------------------

module "iam_policies" {
  source = "../../../modules/iam-policy"

  policies = local.iam_policies_resolved
}

# ---------------------------------------------------------------------------
# VPC Peering, Connect factory projects to hub VPC
# ---------------------------------------------------------------------------

module "vpc_peerings" {
  source   = "../../../modules/vpc-peering"
  for_each = length(local.vpc_peerings) > 0 ? { "default" = true } : {}

  region = var.region

  peering_connections = {
    for k, v in local.vpc_peerings : k => {
      name            = lookup(v, "name", "lz-${local.environment}-peering-${k}")
      source_vpc_id   = local.hub_vpc_id
      target_vpc_id   = module.factory_vpcs[v.project_key].id
      source_vpc_cidr = lookup(v, "source_vpc_cidr", null)
      target_vpc_cidr = lookup(v, "target_vpc_cidr", null)
      tags            = concat(local.common_tags, lookup(v, "tags", []))
    }
  }
}

# ---------------------------------------------------------------------------
# Object Storage, Optional per-project buckets
# ---------------------------------------------------------------------------

module "object_buckets" {
  source   = "../../../modules/object-storage"
  for_each = { for k, v in local.object_buckets : k => v }

  name        = "lz-${local.environment}-${each.value.name}"
  project_id  = module.projects[each.value.project_key].id
  region      = var.region
  tags        = merge(local.common_tags_map, lookup(each.value, "tags", {}))
  enable_lock = lookup(each.value, "enable_lock", false)
  enable_sse  = lookup(each.value, "enable_sse", true)
}

