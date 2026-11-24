variable "name" {

  description = "Name of the bucket."
  type        = string
}

variable "project_id" {
  description = "Scaleway Project ID for the bucket."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "enable_lock" {
  description = "Enable object lock (WORM) for the bucket."
  type        = bool
  default     = false
}

variable "enable_sse" {
  description = "Enable server-side encryption (SSE-AES256) for the bucket."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Purge all objects and delete the bucket even with Object Lock (replacement-safe)."
  type        = bool
  default     = false
}
