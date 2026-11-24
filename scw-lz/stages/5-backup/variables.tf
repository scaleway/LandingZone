variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

variable "infra_ops_project_id" {
  description = "ID of the infra-ops project (bootstrap's project) - hosts the terraform state bucket the state-sync copy reads."
  type        = string
}

variable "lz_project_id" {
  description = "ID of the lz-<env> project - home of the backup/DR buckets, KMS, jobs, secrets and exporter (written by bootstrap into 5-backup-<env>.tfvars)."
  type        = string
}

variable "region" {
  description = "Scaleway region for the backup stack (home of the primary bucket + the sync job)."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone."
  type        = string
  default     = "fr-par-2"
}

variable "environment" {
  description = "Environment name (dev, prod). Used for naming."
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

variable "state_bucket_name" {
  description = "Name of the terraform state bucket (source of the cross-region DR copy)."
  type        = string
}

variable "state_endpoint" {
  description = "S3-compatible endpoint of the state bucket."
  type        = string
}

variable "state_bucket" {
  description = "Name of the state bucket (for the stage-2 remote state data source)."
  type        = string
}

variable "state_access_key" {
  description = "Access key for reading prior stages' remote state."
  type        = string
  sensitive   = true
}

variable "state_secret_key" {
  description = "Secret key for reading prior stages' remote state."
  type        = string
  sensitive   = true
}

# Present in the shared remote_state-<env>.tfvars (written by bootstrap); used
# here by the bootstrap remote-state data source (backend = local) to read the
# frozen bucket-uniqueness timestamp for the fallback bucket names.
variable "stage0_state_path" {
  description = "Path (relative to this stage dir) of the bootstrap LOCAL state file - read via data.terraform_remote_state.bootstrap to derive the bucket_suffix fallback."
  type        = string
  default     = ""
}

variable "backup_bucket_name" {
  description = "Name of the primary backup bucket (fr-par). Empty = convention lz-<env>-backup-<timestamp> (frozen creation suffix, from the bootstrap bucket_suffix output)."
  type        = string
  default     = ""
}

variable "backup_bucket_endpoint" {
  description = "S3-compatible endpoint of the primary backup bucket."
  type        = string
}

variable "backup_dr_bucket_name" {
  description = "Name of the cross-region DR backup bucket. Empty = convention lz-<env>-backup-dr-<timestamp> (frozen creation suffix)."
  type        = string
  default     = ""
}

variable "backup_dr_bucket_endpoint" {
  description = "S3-compatible endpoint of the DR backup bucket."
  type        = string
}

variable "backup_dr_region" {
  description = "Region of the DR backup bucket."
  type        = string
}

# --- bucket stack knobs (rendered into 5-backup-<env>.tfvars by bootstrap) ---

variable "backup_retention_days" {
  description = "Retention in days for noncurrent versions in the backup buckets (lifecycle expiration)."
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

variable "sync_schedule" {
  description = "Cron schedule for the state -> primary backup copy job (UTC)."
  type        = string
  default     = "0 2 * * *"
}

variable "dr_sync_schedule" {
  description = "Cron schedule for the primary -> cross-region DR mirror job (UTC). Runs after the state sync so the freshest state copy is included."
  type        = string
  default     = "5 2 * * *"
}

variable "sync_timezone" {
  description = "Timezone for the sync job cron schedule."
  type        = string
  default     = "UTC"
}

variable "sync_job_image" {
  description = "Container image for the sync job (rclone). Running in daily production use."
  type        = string
  default     = "rclone/rclone:latest"
}

variable "api_key_expires_at" {
  description = "Expiration date for the backup API key (RFC3339 format). Null = never expires."
  type        = string
  default     = null
}

# --- firewall config exporter (Phase B) --------------------------------------

variable "fw_export_hosts" {
  description = "Comma-separated firewall LAN IPs the exporter pulls config from. Empty (default) = resolved automatically from stage-3 state (fw_passive_lan_ip,fw_active_lan_ip)."
  type        = string
  default     = ""
}

variable "fw_export_user" {
  description = "SSH user the exporter connects as on the firewalls."
  type        = string
  default     = "root"
}

variable "fw_export_prefix" {
  description = "Object prefix in the backup bucket for firewall config exports."
  type        = string
  default     = "firewall/config"
}

variable "fw_logs_prefix" {
  description = "Object prefix in the backup bucket for bounded firewall log exports."
  type        = string
  default     = "firewall/logs"
}

variable "fw_config_retention_days" {
  description = "Prune firewall CONFIG exports older than this many days (primary bucket; DR keeps everything). Lifecycle can't do age-based current-version deletion (provider bug), so the exporter prunes."
  type        = number
  default     = 90
}

variable "fw_logs_retention_days" {
  description = "Prune firewall LOG exports older than this many days (primary bucket)."
  type        = number
  default     = 30
}

variable "fw_export_image" {
  description = "Container image for the firewall config exporter. Alpine-based; ssh/rclone/python3 are provisioned at cold start."
  type        = string
  default     = "alpine:3.20"
}

variable "fw_export_cron_schedule" {
  description = "UNIX cron schedule for the firewall config export (UTC). Runs after the DR mirror so the export is picked up the same day."
  type        = string
  default     = "30 2 * * *"
}

variable "fw_backup_key_file" {
  description = "Path to the firewall backup SSH private key (gitignored). Empty = scw-lz/keys-<env>/fw-backup/id_ed25519."
  type        = string
  default     = ""
}
