variable "name" {
  description = "Name of the KMS key."
  type        = string
}

variable "description" {
  description = "Description of the KMS key."
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

variable "algorithm" {
  description = "Algorithm to use for the key."
  type        = string
  default     = "aes_256_gcm"
}

variable "usage" {
  description = "Key usage type. Possible values: symmetric_encryption, asymmetric_encryption, asymmetric_signing."
  type        = string
  default     = "symmetric_encryption"
}

variable "unprotected" {
  description = "Whether the key is unprotected. If false, the key is protected and cannot be deleted."
  type        = bool
  default     = false
}


