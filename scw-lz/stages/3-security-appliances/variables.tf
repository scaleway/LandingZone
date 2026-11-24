# ---------------------------------------------------------------------------
# Stage 3 - Security Appliances: Variables
# Rebuilt with the blueprint method (HA OPNsense pair via the firewall module).
#
# DESIGN DATA is declared once in the per-env config folder
# (envs/<env>/data/security-appliances-<env>.yaml: zones, IP plan, image
# settings, feature flags, test instances) and consumed via `yamldecode` in
# main.tf - mirrors stages 0/1/2/4. This file keeps only:
#   1. provider/backend wiring (passed by the per-env providers/remote_state tfvars)
#   2. OPNsense secrets + SSH keys (gitignored tfvars)
#   3. firewall image S3 upload credentials (gitignored tfvars)
#   4. common_tags: the org-wide resource tag policy (below)
# ---------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (dev, prod)"
  type        = string
  default     = "dev"
}

variable "project_key" {
  description = "Key of the project from bootstrap to deploy into (e.g., 'dev')"
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Scaleway region"
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway zone used for public gateways and non-fw resources"
  type        = string
  default     = "fr-par-2"
}

variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
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

# ---------------------------------------------------------------------------
# OPNsense secrets - never commit real values.
# ---------------------------------------------------------------------------

variable "opnsense_root_password" {
  description = "OPNsense root (XMLRPC sync) password; inject through a secret variable."
  type        = string
  sensitive   = true
}

variable "opnsense_root_password_hash" {
  description = "Bcrypt hash matching the OPNsense root password."
  type        = string
  sensitive   = true
  validation {
    condition     = can(regex("^\\$2[aby]\\$[0-9]{2}\\$", var.opnsense_root_password_hash))
    error_message = "opnsense_root_password_hash must be a bcrypt hash beginning with $2a$, $2b$ or $2y$."
  }
}

variable "carp_password" {
  description = "Shared CARP secret used by the OPNsense HA pair."
  type        = string
  sensitive   = true
}

variable "vm_ssh_public_key" {
  description = "DEPRECATED - not used by stage-3 anymore (test spokes get the bootstrap admin key via remote state). Kept only so existing tfvars (prod) keep parsing; safe to remove from tfvars."
  type        = string
  default     = ""
  validation {
    condition     = var.vm_ssh_public_key == "" || can(regex("^ssh-(ed25519|rsa|ecdsa) ", trimspace(var.vm_ssh_public_key)))
    error_message = "vm_ssh_public_key must be an OpenSSH public key (or empty)."
  }
}

# SSH keys are AUTOMATED in main.tf (locals.fw_admin_ssh_key /
# fw_backup_ssh_key): the admin key defaults to bootstrap's live
# ssh_public_keys["admin_key"] and the backup exporter key defaults to
# scw-lz/keys-<env>/fw-backup/id_ed25519.pub. These overrides are optional - leave
# "" to use the automated source.
variable "opnsense_ssh_public_key" {
  description = "OPTIONAL override: SSH public key for root key-only OPNsense access. Defaults to bootstrap's live admin key (tracks the spokes - no drift). Empty string = auto."
  type        = string
  default     = ""
  validation {
    condition     = var.opnsense_ssh_public_key == "" || can(regex("^ssh-(ed25519|rsa|ecdsa) ", trimspace(var.opnsense_ssh_public_key)))
    error_message = "opnsense_ssh_public_key must be an OpenSSH public key (or empty for the automated bootstrap admin key)."
  }
}

variable "opnsense_backup_ssh_public_key" {
  description = "OPTIONAL override: SSH public key of the DEDICATED firewall backup exporter (scw-lz/keys-<env>/fw-backup/). Appended to root's authorized keys so the serverless exporter (lz-<env>-fw-export) can pull config.xml. Defaults to the local key file; empty string = auto."
  type        = string
  default     = ""
  validation {
    condition     = var.opnsense_backup_ssh_public_key == "" || can(regex("^ssh-(ed25519|rsa|ecdsa) ", trimspace(var.opnsense_backup_ssh_public_key)))
    error_message = "opnsense_backup_ssh_public_key must be an OpenSSH public key (or empty for the automated key file)."
  }
}

# ---------------------------------------------------------------------------
# Firewall image S3 upload credentials - merged into the image config from
# the per-env security-appliances factory (envs/<env>/data/
# security-appliances-<env>.yaml, local.fw_image_1/_2 in main.tf).
# ---------------------------------------------------------------------------

variable "upload_access_key" {
  description = "S3 access key that uploads the firewall image object to the bucket (enable_upload only)."
  type        = string
  sensitive   = true
  default     = ""
}

variable "upload_secret_key" {
  description = "S3 secret key that uploads the firewall image object to the bucket (enable_upload only)."
  type        = string
  sensitive   = true
  default     = ""
}

# ---------------------------------------------------------------------------
# Golden firewall image: the image bucket + per-zone SBS snapshots live in
# THIS stage (lz-<env> project). The upload-wait gate delivers the qcow2
# (bundled file or source_url) into the bucket and blocks the snapshot import
# until it is present. The firewalls derive their instance-scoped SBS volumes
# from the snapshots this stage imports from that same-project bucket.
# ---------------------------------------------------------------------------

variable "image_bucket_name" {
  description = "Name of the golden firewall image bucket (created by this stage in the lz-<env> project). Defaults to the factory yaml value or <state_bucket_prefix>-<env>-image-import."
  type        = string
  default     = ""
}

variable "state_bucket_prefix" {
  description = "User prefix shared with the bootstrap buckets. In THIS stage it drives only the image-import bucket name (<prefix>-<env>-image-import-<timestamp>) - set the same value as the bootstrap stage's state_bucket_prefix (0-org-setup-<env>.tfvars) to keep all bootstrap-named buckets unique per user. Null keeps the historical default lz; the timestamp suffix is added automatically from the bootstrap output."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Remote State Backend Config (from bootstrap)
# ---------------------------------------------------------------------------

variable "state_bucket" {
  description = "Name of the Terraform state bucket (created by bootstrap)."
  type        = string
  default     = ""
}

variable "state_endpoint" {
  description = "Endpoint of the S3-compatible state bucket."
  type        = string
  default     = ""
}

variable "state_access_key" {
  description = "Access key for the state bucket."
  type        = string
  default     = ""
}

variable "state_secret_key" {
  description = "Secret key for the state bucket."
  type        = string
  default     = ""
}

variable "stage0_state_path" {
  description = "Path (relative to this stage dir) of the bootstrap LOCAL state file - source of project_ids, ssh_public_keys, environment. Written by bootstrap into remote_state-<env>.tfvars."
  type        = string
}
