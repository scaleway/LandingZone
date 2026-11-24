variable "name" {
  description = "Name of the security group"
  type        = string
}

variable "description" {
  description = "Description of the security group"
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway project ID"
  type        = string
  default     = null
}

variable "zone" {
  description = "Scaleway zone"
  type        = string
  default     = null
}

variable "stateful" {
  description = "Whether the security group is stateful"
  type        = bool
  default     = true
}

variable "inbound_default_policy" {
  description = "Default inbound policy: accept or drop"
  type        = string
  default     = "drop"
}

variable "outbound_default_policy" {
  description = "Default outbound policy: accept or drop"
  type        = string
  default     = "accept"
}

variable "enable_default_security" {
  description = "Enable Scaleway's default security rules"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the security group"
  type        = list(string)
  default     = []
}

variable "inbound_rules" {
  description = "List of inbound rules"
  type = list(object({
    action     = string
    protocol   = optional(string, "TCP")
    port       = optional(number)
    port_range = optional(string)
    ip_range   = optional(string)
  }))
  default = []
}

variable "outbound_rules" {
  description = "List of outbound rules"
  type = list(object({
    action     = string
    protocol   = optional(string, "TCP")
    port       = optional(number)
    port_range = optional(string)
    ip_range   = optional(string)
  }))
  default = []
}