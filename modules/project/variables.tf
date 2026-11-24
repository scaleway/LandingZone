variable "name" {
  description = "The name of the Project."
  type        = string
}

variable "description" {
  description = "The description of the Project."
  type        = string
  default     = null
}

variable "organization_id" {
  description = "The organization ID the Project is associated with."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Optional existing project ID to reference instead of creating a new one. When set, the module uses a data source to reference the existing project and does NOT create a new resource."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to resources created by this module (propagated to inline IAM policies). Note: `scaleway_account_project` does not support tags natively."
  type        = list(string)
  default     = []
}

variable "iam_policies" {
  description = "Map of IAM policies to create alongside the project (one-call IAM wiring pattern)."
  type        = any
  default     = {}
}