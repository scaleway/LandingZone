# --------------------------------------------------------------------------
# Factory-style map interface (recommended)
# --------------------------------------------------------------------------

variable "policies" {
  description = "Map of IAM policies to create (factory-style). Each key is the policy key; each value supports: name (optional, defaults to key), description, tags, user_id/group_id/application_id/no_principal, and rules (list of { organization_id, project_ids, permission_set_names, condition })."
  type        = any
  default     = {}
}

# --------------------------------------------------------------------------
# Legacy single-policy interface (kept for backward compatibility)
# --------------------------------------------------------------------------

variable "name" {
  description = "(LEGACY) The name of the IAM policy. Only used when `policies` is empty."
  type        = string
  default     = null
}

variable "description" {
  description = "(LEGACY) The description of the IAM policy."
  type        = string
  default     = null
}

variable "tags" {
  description = "(LEGACY) The tags associated with the IAM policy."
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = "The ID of the organization the policy is associated with (also used as default for factory policies)."
  type        = string
  default     = null
}

variable "user_id" {
  description = "(LEGACY) ID of the user the policy will be linked to."
  type        = string
  default     = null
}

variable "group_id" {
  description = "(LEGACY) ID of the group the policy will be linked to."
  type        = string
  default     = null
}

variable "application_id" {
  description = "(LEGACY) ID of the application the policy will be linked to."
  type        = string
  default     = null
}

variable "no_principal" {
  description = "(LEGACY) If the policy doesn't apply to a principal."
  type        = bool
  default     = false
}

variable "rules" {
  description = "(LEGACY) List of rules in the policy."
  type = list(object({
    project_ids          = optional(list(string))
    organization_id      = optional(string)
    permission_set_names = list(string)
    condition            = optional(string)
  }))
  default = []
}
