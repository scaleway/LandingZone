/**
 * Stage 5, Backup
 * Cross-region DR owning its buckets in the lz-<env> project: backup IAM
 * identity (two default-project-scoped keys: infra-ops for state reads,
 * lz-<env> for bucket writes), KMS keys, a daily state-sync job, a
 * cross-region DR mirror, and the firewall config exporter. Copy-only by
 * design (no --delete): DR keeps objects the primary lost.
 */

terraform {
  required_version = ">= 1.5"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    key = "stage-5/terraform.tfstate"
  }
}

provider "scaleway" {
  organization_id = var.organization_id
  # Backup stack lives in the lz-<env> project; id comes from the
  # bootstrap-written 5-backup tfvars (single source of truth).
  project_id = var.lz_project_id
  region     = var.region
  zone       = var.zone
}

# Stage-2 state: only for the hub LAN PN ID the exporter attaches to (10.10.0.x).
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

# Stage-3 state: only for the firewall LAN IPs the exporter pulls from
# (resolved so FW_HOSTS matches the CARP pair; override via fw_export_hosts).
data "terraform_remote_state" "stage3" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-3/terraform.tfstate"
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

# Bootstrap state: just for the frozen bucket-uniqueness suffix (keeps bare
# runs collision-free; bootstrap tfvars always carry the real suffixed names).
data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    # Path written by bootstrap into remote_state-<env>.tfvars (stage0_state_path).
    path = var.stage0_state_path
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
  environment = var.environment
  stage_id    = "stage5"
}

locals {
  common_tags     = module.common_tags.list
  common_tags_map = module.common_tags.map

  hub_lan_private_network_id = data.terraform_remote_state.stage2.outputs.private_network_ids["hub"]["hub-net"]

  # Exporter's FW LAN IPs, resolved from the deployed CARP pair (overridable).
  # lookup=>"" on stale remote state so a destroy plan never breaks.
  fw_export_hosts = var.fw_export_hosts != "" ? var.fw_export_hosts : join(
    ",", compact([
      lookup(data.terraform_remote_state.stage3.outputs, "fw_passive_lan_ip", ""),
      lookup(data.terraform_remote_state.stage3.outputs, "fw_active_lan_ip", ""),
    ])
  )

  # Bucket names: lz-<env>-backup[-dr] unless tfvars override. Fallbacks append
  # the frozen bucket_suffix so even a bare run stays globally unique.
  bucket_suffix         = lookup(data.terraform_remote_state.bootstrap.outputs, "bucket_suffix", "")
  backup_bucket_name    = var.backup_bucket_name != "" ? var.backup_bucket_name : "lz-${var.environment}-backup${local.bucket_suffix == "" ? "" : "-${local.bucket_suffix}"}"
  backup_dr_bucket_name = var.backup_dr_bucket_name != "" ? var.backup_dr_bucket_name : "lz-${var.environment}-backup-dr${local.bucket_suffix == "" ? "" : "-${local.bucket_suffix}"}"
}

# ---------------------------------------------------------------------------
# KMS keys, one symmetric key per region. Object Storage can't do SSE-KMS
# yet, so the buckets use AES256 SSE; these are reserved for other KMS uses.
# Unprotected (deletable) so IaC can rotate them.
# ---------------------------------------------------------------------------

resource "scaleway_key_manager_key" "backup" {
  name        = "lz-${var.environment}-backup-key"
  description = "Key Manager key for the backup stack (${var.region}) - reserved; SSE-KMS not yet served by Object Storage"
  region      = var.region
  project_id  = var.lz_project_id
  usage       = "symmetric_encryption"
  algorithm   = "aes_256_gcm"
  unprotected = true
  tags        = concat(local.common_tags, ["backup", "sse-kms"])

  rotation_policy {
    rotation_period = "${var.kms_key_rotation_days * 24}h"
  }
}

resource "scaleway_key_manager_key" "backup_dr" {
  name        = "lz-${var.environment}-backup-dr-key"
  description = "Key Manager key for the backup stack (${var.backup_dr_region}) - reserved; SSE-KMS not yet served by Object Storage"
  region      = var.backup_dr_region
  project_id  = var.lz_project_id
  usage       = "symmetric_encryption"
  algorithm   = "aes_256_gcm"
  unprotected = true
  tags        = concat(local.common_tags, ["backup-dr", "sse-kms"])

  rotation_policy {
    rotation_period = "${var.kms_key_rotation_days * 24}h"
  }
}

# ---------------------------------------------------------------------------
# Backup buckets (primary + DR), owned in lz-<env>. Versioned, NOT object-locked
# (a WORM lock would fight lifecycle rotation). No native cross-region
# replication, so DR is a scheduled copy. Provider bug (2.82.0): lifecycle
# can't expire current versions (ExpiredObjectDeleteMarker is rejected by S3),
# so age-based retention is the backup job's prune step; lifecycle only cleans
# noncurrent versions + aborted multipart uploads.
# ---------------------------------------------------------------------------

resource "scaleway_object_bucket" "backup" {
  name       = local.backup_bucket_name
  project_id = var.lz_project_id
  region     = var.region
  tags       = merge(local.common_tags_map, { purpose = "backup" })
  versioning {
    enabled = var.enable_backup_versioning
  }
  lifecycle_rule {
    id      = "version-cleanup"
    enabled = true
    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
  lifecycle_rule {
    id                                     = "abort-incomplete"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }
}

resource "scaleway_object_bucket" "backup_dr" {
  name       = local.backup_dr_bucket_name
  project_id = var.lz_project_id
  region     = var.backup_dr_region
  tags       = merge(local.common_tags_map, { purpose = "backup-dr" })
  versioning {
    enabled = var.enable_backup_versioning
  }
  lifecycle_rule {
    id      = "version-cleanup"
    enabled = true
    noncurrent_version_expiration {
      noncurrent_days = var.backup_retention_days
    }
  }
  lifecycle_rule {
    id                                     = "abort-incomplete"
    enabled                                = true
    abort_incomplete_multipart_upload_days = 7
  }
}

resource "scaleway_object_bucket_server_side_encryption_configuration" "backup" {
  count      = var.enable_backup_sse ? 1 : 0
  bucket     = scaleway_object_bucket.backup.name
  region     = var.region
  project_id = var.lz_project_id
  rule {
    apply_server_side_encryption_by_default {
      # SSE-KMS is not honored: an aws:kms-default bucket fails every PutObject
      # with 500 InternalError. AES256 only, the KMS keys above serve other uses.
      sse_algorithm = "AES256"
    }
  }
}

resource "scaleway_object_bucket_server_side_encryption_configuration" "backup_dr" {
  count      = var.enable_backup_sse ? 1 : 0
  bucket     = scaleway_object_bucket.backup_dr.name
  region     = var.backup_dr_region
  project_id = var.lz_project_id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Backup IAM identity. Raw S3 follows the key's DEFAULT PROJECT, so the SA
# gets two keys: #1 defaulted to infra-ops (state reads), #2 to lz-<env>
# (bucket writes).
# ---------------------------------------------------------------------------

module "backup_sa" {
  source = "../../../modules/iam-service-account"

  name                       = "lz-${var.environment}-backup"
  description                = "Backup stack service account (cross-region sync, exports)"
  organization_id            = var.organization_id
  create_api_key             = true
  api_key_description        = "API key for the backup service account (default project = infra-ops, state reads)"
  api_key_expires_at         = var.api_key_expires_at
  api_key_default_project_id = var.infra_ops_project_id
}

resource "scaleway_iam_api_key" "backup_env_key" {
  application_id     = module.backup_sa.id
  description        = "API key for the backup service account (default project = lz-${var.environment}, bucket writes)"
  default_project_id = var.lz_project_id
  expires_at         = var.api_key_expires_at
}

module "backup_policies" {
  source = "../../../modules/iam-policy"

  organization_id = var.organization_id

  policies = {
    # NOTE: org id must be null on the ENTRY: a rule can't carry both an org
    # scope and project_ids (RuleSpecs.scope oneof). The policy gets its org
    # from the module-level variable below; the rule stays project-scoped.
    backup = {
      name            = "lz-${var.environment}-backup"
      description     = "Backup SA: object storage on the lz-${var.environment} project + state-bucket read on infra-ops"
      organization_id = null
      application_id  = module.backup_sa.id
      rules = [
        {
          project_ids = [var.lz_project_id]
          # ObjectStorageFullAccess = sync/export to the backup buckets;
          # ContainersPrivateAccess = invoke the private exporter during restore.
          permission_set_names = ["ObjectStorageFullAccess", "ContainersPrivateAccess"]
        },
        {
          project_ids = [var.infra_ops_project_id]
          # State bucket (infra-ops) read for the sync; raw S3 is key-scoped,
          # hence key #1 above defaulted to infra-ops.
          permission_set_names = ["ObjectStorageReadOnly"]
        },
      ]
    }
  }
}

# ---------------------------------------------------------------------------
# Backup credentials in Secret Manager, shells via the secrets module, values
# as write-only versions (data_wo) so they never land in state. Both key pairs.
# ---------------------------------------------------------------------------

module "backup_credentials" {
  source = "../../../modules/secrets"
  for_each = {
    access_key = {
      name        = "lz-${var.environment}-backup-access-key"
      description = "Access key of the backup service account (infra-ops scope, S3)"
    }
    secret_key = {
      name        = "lz-${var.environment}-backup-secret-key"
      description = "Secret key of the backup service account (infra-ops scope, S3)"
    }
    env_access_key = {
      name        = "lz-${var.environment}-backup-env-access-key"
      description = "Access key of the backup service account (lz-${var.environment} scope, S3)"
    }
    env_secret_key = {
      name        = "lz-${var.environment}-backup-env-secret-key"
      description = "Secret key of the backup service account (lz-${var.environment} scope, S3)"
    }
  }

  name        = each.value.name
  description = each.value.description
  project_id  = var.lz_project_id
  region      = var.region
  tags        = concat(local.common_tags, ["backup", "credentials"])
  # secret_value intentionally null: versions are created below with data_wo
}

resource "scaleway_secret_version" "backup_credentials" {
  for_each = {
    access_key = {
      secret_id = module.backup_credentials["access_key"].id
      value     = module.backup_sa.access_key
    }
    secret_key = {
      secret_id = module.backup_credentials["secret_key"].id
      value     = module.backup_sa.secret_key
    }
    env_access_key = {
      secret_id = module.backup_credentials["env_access_key"].id
      value     = scaleway_iam_api_key.backup_env_key.access_key
    }
    env_secret_key = {
      secret_id = module.backup_credentials["env_secret_key"].id
      value     = scaleway_iam_api_key.backup_env_key.secret_key
    }
  }

  secret_id = each.value.secret_id
  region    = var.region
  data_wo   = each.value.value
}

# ---------------------------------------------------------------------------
# State sync job: rclone mirror of the state bucket (infra-ops) into the
# primary backup bucket. Explicit per-remote credentials, raw S3 follows the
# key's default project, so src = infra-ops key, dst = lz-<env> key. Keys come
# from Secret Manager, never state. Copy-only (no --delete).
# ---------------------------------------------------------------------------

module "state_sync" {
  source = "../../../modules/serverless-job"

  name        = "lz-${var.environment}-state-sync"
  description = "Daily copy of terraform state into the primary backup bucket (${var.region})"
  project_id  = var.lz_project_id
  region      = var.region
  image_uri   = var.sync_job_image
  # Pin retries to 0: the API defaults max_retries=0 when the block is omitted,
  # so pinning prevents perpetual "retry_policy: 0 -> null" drift on plan.
  retry_max_retries = 0
  # State files only: the 2.19 GB firewall golden image is excluded, not
  # needed for DR (FW recovery uses imported snapshots) and would blow the
  # ~2 MB/s egress window. State-only runs finish in seconds.
  timeout = "10m"

  startup_command = [
    "rclone", "sync",
    "src:${var.state_bucket_name}",
    "dst:${local.backup_bucket_name}/terraform-state",
    "--exclude", "images/**",
    "--check-first",
    "--checksum",
  ]

  env = {
    "RCLONE_CONFIG_SRC_TYPE"     = "s3"
    "RCLONE_CONFIG_SRC_PROVIDER" = "Scaleway"
    "RCLONE_CONFIG_SRC_ENDPOINT" = var.state_endpoint
    "RCLONE_CONFIG_SRC_REGION"   = var.region
    "RCLONE_CONFIG_DST_TYPE"     = "s3"
    "RCLONE_CONFIG_DST_PROVIDER" = "Scaleway"
    "RCLONE_CONFIG_DST_ENDPOINT" = var.backup_bucket_endpoint
    "RCLONE_CONFIG_DST_REGION"   = var.region
  }

  secret_references = [
    # src remote = infra-ops scope (state bucket)
    {
      secret_id   = module.backup_credentials["access_key"].id
      environment = "RCLONE_CONFIG_SRC_ACCESS_KEY_ID"
    },
    {
      secret_id   = module.backup_credentials["secret_key"].id
      environment = "RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY"
    },
    # dst remote = lz-<env> scope (backup bucket)
    {
      secret_id   = module.backup_credentials["env_access_key"].id
      environment = "RCLONE_CONFIG_DST_ACCESS_KEY_ID"
    },
    {
      secret_id   = module.backup_credentials["env_secret_key"].id
      environment = "RCLONE_CONFIG_DST_SECRET_ACCESS_KEY"
    },
  ]

  cron_schedule = var.sync_schedule
  cron_timezone = var.sync_timezone
}

# ---------------------------------------------------------------------------
# DR mirror job: rclone full mirror of the primary backup bucket to the
# cross-region bucket (fr-par -> nl-ams), new backup sources need no DR
# plumbing changes. Copy-only (no --delete): DR keeps objects pruned from the
# primary (long-term archive); --check-first --checksum rolls it forward.
# Both remotes are lz-<env>-scope, so the lz-<env> key is used for both.
# Runs 5 min after the state sync so the freshest state copy is included.
# ---------------------------------------------------------------------------

module "dr_sync" {
  source = "../../../modules/serverless-job"

  name        = "lz-${var.environment}-dr-sync"
  description = "Daily cross-region mirror of the full backup bucket (${var.region} -> ${var.backup_dr_region}) via rclone"
  project_id  = var.lz_project_id
  region      = var.region
  image_uri   = var.sync_job_image
  # Pin retries to 0 (see state_sync above) to avoid plan drift.
  retry_max_retries = 0
  timeout           = "10m"

  startup_command = [
    "rclone", "sync",
    "src:${local.backup_bucket_name}",
    "dst:${local.backup_dr_bucket_name}",
    "--check-first",
    "--checksum",
  ]

  env = {
    "RCLONE_CONFIG_SRC_TYPE"     = "s3"
    "RCLONE_CONFIG_SRC_PROVIDER" = "Scaleway"
    "RCLONE_CONFIG_SRC_ENDPOINT" = var.backup_bucket_endpoint
    "RCLONE_CONFIG_SRC_REGION"   = var.region
    "RCLONE_CONFIG_DST_TYPE"     = "s3"
    "RCLONE_CONFIG_DST_PROVIDER" = "Scaleway"
    "RCLONE_CONFIG_DST_ENDPOINT" = var.backup_dr_bucket_endpoint
    "RCLONE_CONFIG_DST_REGION"   = var.backup_dr_region
  }

  secret_references = [
    {
      secret_id   = module.backup_credentials["env_access_key"].id
      environment = "RCLONE_CONFIG_SRC_ACCESS_KEY_ID"
    },
    {
      secret_id   = module.backup_credentials["env_secret_key"].id
      environment = "RCLONE_CONFIG_SRC_SECRET_ACCESS_KEY"
    },
    {
      secret_id   = module.backup_credentials["env_access_key"].id
      environment = "RCLONE_CONFIG_DST_ACCESS_KEY_ID"
    },
    {
      secret_id   = module.backup_credentials["env_secret_key"].id
      environment = "RCLONE_CONFIG_DST_SECRET_ACCESS_KEY"
    },
  ]

  cron_schedule = var.dr_sync_schedule
  cron_timezone = var.sync_timezone
}

# ---------------------------------------------------------------------------
# Firewall backup SSH key (scw-lz/keys-<env>/fw-backup/, gitignored) mirrored
# into Secret Manager as a write-only version (data_wo, never in state); the
# public half is composed into stage-3's authorized keys.
# ---------------------------------------------------------------------------

module "fw_backup_key_secret" {
  source = "../../../modules/secrets"

  name        = "lz-${var.environment}-fw-backup-key"
  description = "Private SSH key of the firewall backup exporter"
  project_id  = var.lz_project_id
  region      = var.region
  tags        = concat(local.common_tags, ["backup", "firewall", "ssh"])
}

resource "scaleway_secret_version" "fw_backup_key" {
  secret_id = module.fw_backup_key_secret.id
  region    = var.region
  data_wo   = file(var.fw_backup_key_file != "" ? var.fw_backup_key_file : "${path.module}/../../keys-${var.environment}/fw-backup/id_ed25519")
}

# ---------------------------------------------------------------------------
# Firewall config exporter: private serverless container on the hub LAN PN
# (reaches the FWs at 10.10.0.x), one export per HTTP invocation, daily cron.
# SSH key + lz-<env>-scoped backup SA creds injected as secret env vars (never
# in state). Writes to lz-<env>-backup/firewall/config/<ts>/fw<N>.xml;
# dr_sync mirrors that cross-region with no extra plumbing.
# ---------------------------------------------------------------------------

module "fw_exporter" {
  source = "../../../modules/serverless-container"

  name        = "lz-${var.environment}-fw-export"
  description = "Firewall config exporter (hub LAN PN, SSH pull -> backup bucket)"
  project_id  = var.lz_project_id
  region      = var.region
  tags        = concat(local.common_tags, ["backup", "firewall", "export"])

  image        = var.fw_export_image
  port         = 8080
  protocol     = "http1"
  privacy      = "private"
  min_scale    = 0
  max_scale    = 1
  cpu_limit    = 280
  memory_limit = 512

  private_network_id = local.hub_lan_private_network_id

  command = ["/bin/sh", "-c", file("${path.module}/files/fw-tool.sh")]

  environment_variables = {
    "MODE"                       = "export"
    "FW_HOSTS"                   = local.fw_export_hosts
    "FW_USER"                    = var.fw_export_user
    "BUCKET"                     = local.backup_bucket_name
    "PREFIX_CONFIG"              = var.fw_export_prefix
    "PREFIX_LOGS"                = var.fw_logs_prefix
    "CONFIG_RETENTION_DAYS"      = tostring(var.fw_config_retention_days)
    "LOGS_RETENTION_DAYS"        = tostring(var.fw_logs_retention_days)
    "RCLONE_CONFIG_DST_TYPE"     = "s3"
    "RCLONE_CONFIG_DST_PROVIDER" = "Scaleway"
    "RCLONE_CONFIG_DST_ENDPOINT" = var.backup_bucket_endpoint
    "RCLONE_CONFIG_DST_REGION"   = var.region
  }

  secret_environment_variables = {
    "RCLONE_CONFIG_DST_ACCESS_KEY_ID"     = scaleway_iam_api_key.backup_env_key.access_key
    "RCLONE_CONFIG_DST_SECRET_ACCESS_KEY" = scaleway_iam_api_key.backup_env_key.secret_key
    "FW_SSH_KEY"                          = file(var.fw_backup_key_file != "" ? var.fw_backup_key_file : "${path.module}/../../keys-${var.environment}/fw-backup/id_ed25519")
  }

  cron_schedule    = var.fw_export_cron_schedule
  cron_timezone    = var.sync_timezone
  cron_http_path   = "/"
  cron_http_method = "post"
}
