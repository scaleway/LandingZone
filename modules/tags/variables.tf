# ---------------------------------------------------------------------------
# modules/tags - inputs. Composition (org policy + reserved markers) lives in
# main.tf; these are the only things a stage ever has to feed in.
# ---------------------------------------------------------------------------

variable "user_tags" {
  description = "Org-wide resource tags (key=value) planned by the operator and applied to every resource on top of the toolkit-reserved markers. Keys/values must contain no '=' or ':' (Scaleway rejects ':' in tag values); the reserved keys managed-by / env / stage are injected by this module and rejected here."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.user_tags :
      can(regex("^[^=:]+$", k)) && can(regex("^[^=:]*$", v))
    ])
    error_message = "Tag keys must be non-empty and contain no '=' or ':' (Scaleway tag format is key=value); values must contain no '=' or ':'."
  }

  validation {
    condition = alltrue([
      for k in keys(var.user_tags) :
      !contains(["managed-by", "env", "stage"], k)
    ])
    error_message = "The keys 'managed-by', 'env' and 'stage' are reserved by the toolkit and injected automatically."
  }
}

variable "environment" {
  description = "Environment name (dev, prod). Injected as the reserved `env` tag."
  type        = string
}

variable "stage_id" {
  description = "Stage marker injected as the reserved `stage` tag (e.g. stage1, stage3, bootstrap)."
  type        = string
}

variable "managed_by" {
  description = "Value injected as the reserved `managed-by` tag."
  type        = string
  default     = "landing-zone-toolkit"
}
