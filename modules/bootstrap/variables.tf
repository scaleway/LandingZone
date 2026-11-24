variable "environment" {
  description = "Environment name (dev, prod). Used for naming."
  type        = string
}

variable "tags" {
  description = "Additional resource tags (key=value) applied to the state bucket, on top of the module's functional tags (purpose / managed-by / environment). Usually the stage's common_tags_map."
  type        = map(string)
  default     = {}
}

variable "project_prefix" {
  description = "User prefix for project names: <project_prefix>-<env> (landing-zone project) and <project_prefix>-<env>-infra-ops (infra-ops project). Default 'lz' keeps the historical names."
  type        = string
  default     = "lz"

  validation {
    condition     = var.project_prefix != null && length(var.project_prefix) > 0 && can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.project_prefix))
    error_message = "project_prefix must match ^[a-z0-9][a-z0-9-]{0,20}$ (e.g. lz or acme; max 21 chars)."
  }
}

variable "state_bucket_prefix" {
  description = "User prefix for the state bucket name (e.g. lz-jwang). Bucket names must be globally unique; a frozen creation timestamp is appended automatically (<prefix>-<env>-terraform-state-<timestamp>), so two users can even share a prefix without colliding (each deploy gets a fresh timestamp). REQUIRED."
  type        = string

  # Max 21 chars: the bucket name must stay within Scaleway's 63-char limit
  # (21 prefix + 1 dash + env + 33 '-terraform-state-<16-ch timestamp>' = 62).
  validation {
    condition     = var.state_bucket_prefix != null && length(var.state_bucket_prefix) > 0 && can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.state_bucket_prefix))
    error_message = "state_bucket_prefix is required and must match ^[a-z0-9][a-z0-9-]{0,20}$ (e.g. lz-jwang; max 21 chars so the full bucket name stays within Scaleway's 63-char limit)."
  }
}

variable "infra_ops_project_name" {
  description = "Optional org-wide infra-ops project name shared by all environments (e.g. lz-infra-ops). Null uses the per-env historical default lz-<env>-infra-ops."
  type        = string
  default     = null
}

variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone."
  type        = string
  default     = "fr-par-2"
}

variable "enable_state_lock" {
  description = "Enable object lock (WORM) for the state bucket."
  type        = bool
  default     = true
}

variable "state_retention_days" {
  description = "Retention days for state bucket object lock."
  type        = number
  default     = 365
}

variable "enable_state_sse" {
  description = "Enable server-side encryption for the state bucket."
  type        = bool
  default     = true
}
variable "enable_state_versioning" {
  description = "Enable versioning for the Terraform state bucket."
  type        = bool
  default     = true
}

variable "api_key_expires_at" {
  description = "Expiration date for the bootstrap API key (RFC3339 format). Null = never expires."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# The backup stack (buckets, KMS, jobs, exporter) lives in stage 5 and the
# golden firewall image pipeline in stage 3 (both in the lz-<env> project
# under the deploy key). Bootstrap owns only: infra-ops project, state
# bucket, bootstrap SA/key.
# ---------------------------------------------------------------------------
