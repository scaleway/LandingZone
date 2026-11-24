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

variable "parent_project_key" {
  description = "Key of the project from bootstrap to use as the parent/landing project for provider config."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "Scaleway default region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway default zone."
  type        = string
  default     = "fr-par-2"
}

variable "projects" {
  description = "Map of application/team-level projects to create."
  type = map(object({
    name        = string
    description = optional(string)
    project_id  = optional(string) # reference existing project instead of creating new
    tags        = optional(list(string), [])
  }))
  default = {}
}

variable "iam_groups" {
  description = "Map of IAM groups to create with optional SA/user memberships."
  type = map(object({
    name            = string
    description     = optional(string)
    tags            = optional(list(string), [])
    application_ids = optional(list(string), []) # SA keys from var.service_accounts
    user_ids        = optional(list(string), [])
  }))
  default = {}
}

variable "service_accounts" {
  description = "Map of service accounts (IAM applications) to create for automation."
  type = map(object({
    name                = string
    description         = optional(string)
    tags                = optional(list(string), [])
    project_key         = optional(string) # links to var.projects for default project ID
    create_api_key      = optional(bool, true)
    api_key_description = optional(string, "API key for service account")
    api_key_expires_at  = optional(string)
  }))
  default = {}
}

variable "iam_policies" {
  description = "Map of IAM policies binding permission sets to principals, scoped to projects."
  type        = any
  default     = {}
}

variable "vpc_peerings" {
  description = "Map of VPC peering connections to create between the hub VPC (from Stage 2) and factory projects."
  type = map(object({
    name        = optional(string)
    project_key = string # key into var.projects
    tags        = optional(list(string), [])
  }))
  default = {}
}

variable "object_buckets" {
  description = "Map of object storage buckets to create in factory projects."
  type = map(object({
    name        = string
    project_key = string # key into var.projects
    tags        = optional(map(string), {})
    enable_lock = optional(bool, false)
    enable_sse  = optional(bool, true)
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
