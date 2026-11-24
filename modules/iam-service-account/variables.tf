variable "name" {
  description = "The name of the IAM application (service account)."
  type        = string
}

variable "description" {
  description = "The description of the IAM application."
  type        = string
  default     = null
}

variable "tags" {
  description = "The tags associated with the application."
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = "The ID of the organization the application is associated with."
  type        = string
  default     = null
}

variable "create_api_key" {
  description = "Whether to create an API key for the application."
  type        = bool
  default     = true
}

variable "api_key_description" {
  description = "The description of the API key."
  type        = string
  default     = "API key for service account"
}

variable "api_key_expires_at" {
  description = "The date and time of the expiration of the IAM API key (RFC3339 format)."
  type        = string
  default     = null
}

variable "api_key_default_project_id" {
  description = "The default Project ID to use with Object Storage for the API key."
  type        = string
  default     = null
}
