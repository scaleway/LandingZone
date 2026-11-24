variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

variable "infra_ops_project_name" {
  description = "Optional org-wide infra-ops project name shared by all environments (e.g. lz-infra-ops). Null uses the per-env historical default lz-<env>-infra-ops."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway Project ID to use for bootstrap resources (will use existing project or default)."
  type        = string
  default     = null
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

variable "environment" {
  description = "Environment name (dev, prod)."
  type        = string
  default     = "dev"
}

# ---------------------------------------------------------------------------
# Common resource tags (var.common_tags): the org's own tagging policy, fed
# into module "common_tags" (modules/tags), which appends the toolkit-reserved
# markers managed-by / env / stage on top (single source of truth). Validation
# lives in that module too: keys/values with '=' or ':' are rejected, and the
# reserved keys cannot be set by users.
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Org-wide resource tags (key=value) applied to every resource this stage creates, in addition to the toolkit-reserved managed-by/env/stage markers (applied by modules/tags)."
  type        = map(string)
  default     = {}
}

variable "project_prefix" {
  description = "User prefix for project names: <project_prefix>-<env> (landing-zone project) and <project_prefix>-<env>-infra-ops (infra-ops project). Set your own (e.g. company acronym) so multi-customer orgs can namespace projects; default 'lz' keeps the historical names (lz-dev, lz-dev-infra-ops)."
  type        = string
  default     = "lz"

  validation {
    condition     = var.project_prefix != null && length(var.project_prefix) > 0 && can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.project_prefix))
    error_message = "project_prefix must match ^[a-z0-9][a-z0-9-]{0,20}$ (e.g. lz or acme; max 21 chars)."
  }
}

variable "state_bucket_prefix" {
  description = "User prefix shared by all bootstrap-named buckets (state, audit, image-import, backup/DR). Bucket names must be globally unique; a frozen creation timestamp is appended automatically (<prefix>-<env>-<purpose>-<timestamp>), so even users sharing a prefix never collide. REQUIRED."
  type        = string

  # Max 21 chars: the bucket name must stay within Scaleway's 63-char limit
  # (21 prefix + 1 dash + env + '-' + purpose + 16-ch timestamp).
  validation {
    condition     = var.state_bucket_prefix != null && length(var.state_bucket_prefix) > 0 && can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.state_bucket_prefix))
    error_message = "state_bucket_prefix is required and must match ^[a-z0-9][a-z0-9-]{0,20}$ (e.g. lz-jwang; max 21 chars so the full bucket name stays within Scaleway's 63-char limit)."
  }
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

variable "api_key_expires_at" {
  description = "Expiration date for the bootstrap API key (RFC3339 format). Null = never expires."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Backup stack config, rendered into 5-backup-<env>.tfvars and consumed by
# stage 5, which now OWNS the backup/DR buckets (in the lz-<env> project).
# ---------------------------------------------------------------------------

variable "dr_region" {
  description = "Disaster-recovery region holding the cross-region backup bucket copy."
  type        = string
  default     = "nl-ams"
}

variable "backup_retention_days" {
  description = "Retention in days for objects in the backup buckets (lifecycle expiration)."
  type        = number
  default     = 90
}

variable "enable_backup_versioning" {
  description = "Enable versioning on the backup buckets so historical objects are recoverable."
  type        = bool
  default     = true
}

variable "enable_backup_sse" {
  description = "Enable server-side encryption (AES256) on the backup buckets."
  type        = bool
  default     = true
}

variable "kms_key_rotation_days" {
  description = "Automatic rotation period (days) for the Key Manager keys backing the backup buckets."
  type        = number
  default     = 90
}

# ---------------------------------------------------------------------------
# Org setup. Resource definitions (projects, IAM groups/SAs, policies, SSH
# keys, KMS, audit buckets, secrets, SSO) live in:
# scw-lz/envs/<ENV>/data/org-<ENV>.yaml. The variables below
# override/extend the factory, normally left at their empty defaults.
# ---------------------------------------------------------------------------

variable "projects" {
  description = "Map of projects to create. Overrides/extends the org YAML factory."
  type = map(object({
    name        = string
    description = optional(string)
  }))
  default = {}
}

variable "iam_groups" {
  description = "Map of IAM groups to create. Overrides/extends the org YAML factory."
  type = map(object({
    name            = string
    description     = optional(string)
    tags            = optional(list(string), [])
    application_ids = optional(list(string), [])
    user_ids        = optional(list(string), [])
  }))
  default = {}
}

variable "service_accounts" {
  description = "Map of IAM service accounts (applications) to create. Overrides/extends the org YAML factory."
  type = map(object({
    name                        = string
    description                 = optional(string)
    tags                        = optional(list(string), [])
    create_api_key              = optional(bool, true)
    api_key_description         = optional(string, "API key for service account")
    api_key_expires_at          = optional(string)
    api_key_default_project_id  = optional(string)
    store_key_in_secret_manager = optional(bool, false)
    secret_key                  = optional(string)
  }))
  default = {}
}

variable "iam_policies" {
  description = "Map of IAM policies to create. Overrides/extends the org YAML factory."
  type = map(object({
    name           = string
    description    = optional(string)
    tags           = optional(list(string), [])
    user_id        = optional(string)
    group_id       = optional(string)
    application_id = optional(string)
    no_principal   = optional(bool, false)
    rules = optional(list(object({
      project_ids          = optional(list(string))
      organization_id      = optional(string)
      permission_set_names = list(string)
      condition            = optional(string)
    })), [])
  }))
  default = {}
}

variable "ssh_keys" {
  description = "Map of SSH keys to create. If public_key is omitted, a new key pair will be generated."
  type = map(object({
    name        = string
    public_key  = optional(string)
    algorithm   = optional(string, "ED25519")
    rsa_bits    = optional(number, 4096)
    disabled    = optional(bool, false)
    project_key = optional(string, "dev") # which project to register the key in
  }))
  default = {}
}

variable "kms_keys" {
  description = "Map of KMS keys to create for customer-managed encryption."
  type = map(object({
    name        = string
    description = optional(string)
    project_key = optional(string, "security")
    algorithm   = optional(string, "aes_256_gcm")
    usage       = optional(string, "symmetric_encryption")
    unprotected = optional(bool, false)
  }))
  default = {}
}

variable "audit_log_buckets" {
  description = "Map of Object Storage buckets for centralized audit logs."
  type = map(object({
    name        = string
    project_key = optional(string, "security")
    tags        = optional(map(string), {})
    enable_lock = optional(bool, true)
    enable_sse  = optional(bool, true)
  }))
  default = {}
}

variable "secrets" {
  description = "Map of Secret Manager secrets to create."
  type = map(object({
    name         = string
    description  = optional(string)
    project_key  = optional(string, "security")
    tags         = optional(list(string), [])
    secret_value = optional(string)
  }))
  default = {}
}

variable "sso" {
  description = <<-EOT
    Map of org-level SSO (SAML + SCIM) configurations - at most one entry is
    expected (org-level identity). Managed by modules/iam-sso. Requires
    Terraform >= 1.14 and provider >= 2.83 in this stage. Leave empty/disabled
    for orgs not using identity federation.
  EOT
  type = map(object({
    enabled                            = optional(bool, false)
    entity_id                          = optional(string)
    single_sign_on_url                 = optional(string)
    enable_scim                        = optional(bool, false)
    store_scim_token_in_secret_manager = optional(bool, false)
    project_key                        = optional(string, "security")
    certs = optional(list(object({
      type    = string
      content = string
    })), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Local SSH key storage (managed by this stage, deleted on destroy).
# Per-env convention: '../keys-<env>' (dev -> keys-dev, prod -> keys-prod) so
# test-firewalls.sh and stages 3/5 resolve the same location. The '../keys'
# default is the legacy shared dir (kept for backward compatibility).
# ---------------------------------------------------------------------------
variable "ssh_key_dir" {
  description = "Directory under scw-lz where generated SSH key pairs are stored locally (managed files, deleted on destroy). Use '../keys-<env>' (e.g. keys-dev / keys-prod) to match test-firewalls.sh and stages 3/5."
  type        = string
  default     = "../keys"
}
