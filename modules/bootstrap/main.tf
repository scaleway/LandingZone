/**
 * Bootstrap Module
 *
 * Foundational org infrastructure: the infra-ops project, the remote-state
 * bucket, and the CI/CD service account with its IAM policies.
 *
 * One key per project: only bootstrap works in the infra-ops project. Every
 * other stage runs under the lz-<env> deploy key in the lz-<env> project;
 * both are created by the bootstrap stage (scw-lz/bootstrap).
 */

locals {
  # Bucket prefix, defaulting to lz. Every bucket name below appends a frozen
  # timestamp, so users can share a prefix without colliding.
  resource_prefix = var.state_bucket_prefix != null ? var.state_bucket_prefix : "lz"

  # Project hosting bootstrap resources; one project can be shared org-wide.
  # Default keeps the historical per-env name unless overridden.
  infra_ops_project_name = var.infra_ops_project_name != null ? var.infra_ops_project_name : "${var.project_prefix}-${var.environment}-infra-ops"

  # Frozen timestamp used as the last bucket-name segment
  # (<prefix>-<env>-<purpose>-<timestamp>). time_static pins it once in state
  # so plans stay idempotent; format() with printf padding sidesteps
  # formatdate's 12-hour hour bug; lower() keeps the suffix S3-valid (no T/Z).
  bucket_suffix = lower(format(
    "%04d%02d%02dT%02d%02d%02dZ",
    time_static.bucket_suffix.year,
    time_static.bucket_suffix.month,
    time_static.bucket_suffix.day,
    time_static.bucket_suffix.hour,
    time_static.bucket_suffix.minute,
    time_static.bucket_suffix.second,
  ))
}

# ---------------------------------------------------------------------------
# Infra-ops project
# ---------------------------------------------------------------------------

resource "scaleway_account_project" "infra_ops" {
  name            = local.infra_ops_project_name
  description     = "Project for bootstrap resources, remote state, and CI/CD infrastructure"
  organization_id = var.organization_id
}

# Shared creation timestamp for every bootstrap-named bucket (see locals).
resource "time_static" "bucket_suffix" {}

# ---------------------------------------------------------------------------
# Remote-state bucket (S3-compatible Object Storage)
# ---------------------------------------------------------------------------

resource "scaleway_object_bucket" "terraform_state" {
  name       = "${local.resource_prefix}-${var.environment}-terraform-state-${local.bucket_suffix}"
  project_id = scaleway_account_project.infra_ops.id
  region     = var.region
  tags = merge(var.tags, {
    purpose     = "terraform-state"
    environment = var.environment
    managed-by  = "landing-zone-toolkit"
  })
  object_lock_enabled = var.enable_state_lock
  # Object-locked buckets can't be deleted over plain S3; force_destroy purges
  # the locked objects first, otherwise teardown fails with 409 BucketNotEmpty.
  force_destroy = true
  versioning {
    enabled = var.enable_state_versioning
  }

  # Drain the bucket on destroy: it holds every stage's tfstate and is torn
  # down last, so plain destroy would 409. delete_s3.sh --empty-only clears
  # current + locked/versioned objects. Env is parsed from the bucket name
  # (<prefix>-<env>-terraform-state-<timestamp>).
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      BUCKET="${self.name}"
      base="$${BUCKET%-terraform-state-*}"
      env="$${base##*-}"
      "../../scripts/delete_s3.sh" "$${BUCKET}" "$${env}" --empty-only -y
    EOT
  }
}

resource "scaleway_object_bucket_lock_configuration" "terraform_state" {
  count      = var.enable_state_lock ? 1 : 0
  bucket     = scaleway_object_bucket.terraform_state.name
  region     = var.region
  project_id = scaleway_account_project.infra_ops.id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = var.state_retention_days
    }
  }
}

resource "scaleway_object_bucket_server_side_encryption_configuration" "terraform_state" {
  count      = var.enable_state_sse ? 1 : 0
  bucket     = scaleway_object_bucket.terraform_state.name
  region     = var.region
  project_id = scaleway_account_project.infra_ops.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Bootstrap service account + API key
# ---------------------------------------------------------------------------

resource "scaleway_iam_application" "bootstrap" {
  name            = "lz-${var.environment}-bootstrap"
  description     = "Bootstrap service account for CI/CD pipelines and remote state access"
  organization_id = var.organization_id
}

resource "scaleway_iam_api_key" "bootstrap" {
  application_id     = scaleway_iam_application.bootstrap.id
  description        = "API key for bootstrap service account"
  default_project_id = scaleway_account_project.infra_ops.id
  expires_at         = var.api_key_expires_at

  # The platform back-fills expires_at when the org caps credential lifetimes,
  # which would otherwise force-recreate the key bootstrap drives itself with.
  # Ignore drift; rotate manually.
  lifecycle {
    ignore_changes = [expires_at]
  }
}

# ---------------------------------------------------------------------------
# IAM policies (Scaleway needs one policy per rule scope)
# ---------------------------------------------------------------------------

# Project-scoped: state bucket + secrets in the infra-ops project
resource "scaleway_iam_policy" "bootstrap" {
  name            = "lz-${var.environment}-bootstrap"
  description     = "Bootstrap SA: infra-ops state bucket, secrets, and IAM management"
  application_id  = scaleway_iam_application.bootstrap.id
  organization_id = var.organization_id

  rule {
    project_ids = [scaleway_account_project.infra_ops.id]
    permission_set_names = [
      "ObjectStorageFullAccess",
      "SecretManagerFullAccess",
    ]
  }
}

# Org-wide rights so one key can deploy to every project (VPCs, firewalls, ...).
resource "scaleway_iam_policy" "bootstrap_org_deploy" {
  name            = "lz-${var.environment}-bootstrap-org-deploy"
  description     = "Bootstrap SA: org-wide deployment rights (AllProductsFullAccess)"
  application_id  = scaleway_iam_application.bootstrap.id
  organization_id = var.organization_id

  rule {
    organization_id      = var.organization_id
    permission_set_names = ["AllProductsFullAccess"]
  }
}

# IAMManager can't share a rule with AllProductsFullAccess, so it gets its own
# org-scoped policy.
resource "scaleway_iam_policy" "bootstrap_org_iam" {
  name            = "lz-${var.environment}-bootstrap-org-iam"
  description     = "Bootstrap SA: org-wide IAM management (IAMManager)"
  application_id  = scaleway_iam_application.bootstrap.id
  organization_id = var.organization_id

  rule {
    organization_id      = var.organization_id
    permission_set_names = ["IAMManager"]
  }
}

terraform {
  required_version = ">= 1.5"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
