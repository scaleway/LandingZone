variable "name" {
  description = "The name of the IAM group."
  type        = string
}

variable "description" {
  description = "The description of the IAM group."
  type        = string
  default     = null
}

variable "tags" {
  description = "The tags associated with the group."
  type        = list(string)
  default     = []
}

variable "application_ids" {
  description = "The list of IDs of the applications attached to the group."
  type        = list(string)
  default     = []
}

variable "user_ids" {
  description = "The list of IDs of the users attached to the group."
  type        = list(string)
  default     = []
}

variable "organization_id" {
  description = "The ID of the organization the group is associated with."
  type        = string
  default     = null
}
