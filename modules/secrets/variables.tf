variable "name" {
  description = "Name of the secret."
  type        = string
}

variable "description" {
  description = "Description of the secret."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway Project ID."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags to apply."
  type        = list(string)
  default     = []
}

variable "secret_value" {
  description = "Initial value for the secret. Set to null to skip creating a version."
  type        = string
  default     = null
  sensitive   = true
}
