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

variable "project_key" {
  description = "Key from bootstrap project_ids map to deploy into."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
}

variable "zone" {
  description = "Scaleway zone."
  type        = string
}

variable "security_groups_az1_zone" {
  description = "Zone for the AZ1 duplicate of every security group (zone-scoped in Scaleway). Empty string = no AZ1 duplicates. Prefer the factory key `security_groups_az1_zone`, this variable is a fallback override."
  type        = string
  default     = "fr-par-1"
}

# ---------------------------------------------------------------------------
# Cockpit
# ---------------------------------------------------------------------------

variable "cockpit" {
  description = "Map of Cockpit configurations to create."
  type = map(object({
    name = string
    sources = optional(map(object({
      name           = string
      type           = string
      retention_days = optional(number)
      push_url       = optional(string)
    })), {})
    tokens = optional(map(object({
      name = string
      scopes = optional(object({
        query_metrics       = optional(bool, false)
        write_metrics       = optional(bool, true)
        setup_metrics_rules = optional(bool, false)
        query_logs          = optional(bool, false)
        write_logs          = optional(bool, true)
        setup_logs_rules    = optional(bool, false)
        setup_alerts        = optional(bool, false)
        query_traces        = optional(bool, false)
        write_traces        = optional(bool, false)
      }))
    })), {})
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# KMS Keys
# ---------------------------------------------------------------------------

variable "kms_keys" {
  description = "Map of KMS keys to create."
  type = map(object({
    name        = string
    description = optional(string)
    enabled     = optional(bool, true)
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Secrets
# ---------------------------------------------------------------------------

variable "secrets" {
  description = "Map of Secret Manager secrets to create."
  type = map(object({
    name        = string
    description = optional(string)
    tags        = optional(list(string), [])
  }))
  default = {}
}

# ---------------------------------------------------------------------------
# Security Groups
# ---------------------------------------------------------------------------

variable "security_groups" {
  description = "Map of security groups to create."
  type = map(object({
    name                    = string
    description             = optional(string)
    stateful                = optional(bool, true)
    inbound_default_policy  = optional(string, "drop")
    outbound_default_policy = optional(string, "accept")
    enable_default_security = optional(bool, true)
    tags                    = optional(list(string), [])
    inbound_rules = optional(list(object({
      action     = string
      protocol   = optional(string, "TCP")
      port       = optional(number)
      port_range = optional(string)
      ip_range   = optional(string)
    })), [])
    outbound_rules = optional(list(object({
      action     = string
      protocol   = optional(string, "TCP")
      port       = optional(number)
      port_range = optional(string)
      ip_range   = optional(string)
    })), [])
  }))
  default = {}
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
