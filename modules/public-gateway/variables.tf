variable "name" {
  description = "The name for the Public Gateway."
  type        = string
}

variable "project_id" {
  description = "The ID of the Project the Public Gateway is associated with."
  type        = string
}

variable "zone" {
  description = "The zone in which the Public Gateway should be created."
  type        = string
  default     = "fr-par-2"
}

variable "type" {
  description = "The gateway type (e.g. VPC-GW-S, VPC-GW-M)."
  type        = string
  default     = "VPC-GW-S"
}

variable "tags" {
  description = "The tags to associate with the Public Gateway and IP."
  type        = list(string)
  default     = []
}

variable "create_ip" {
  description = "Whether to create a new flexible IP for the gateway."
  type        = bool
  default     = true
}

variable "ip_id" {
  description = "Attach an existing flexible IP to the gateway (if create_ip is false)."
  type        = string
  default     = null
}

variable "ip_reverse" {
  description = "The reverse domain name for the IP address."
  type        = string
  default     = null
}

variable "bastion_enabled" {
  description = "Enable SSH bastion on the gateway."
  type        = bool
  default     = false
}

variable "bastion_port" {
  description = "The port on which the SSH bastion will listen."
  type        = number
  default     = 61000
}

variable "allowed_ip_ranges" {
  description = "List of IP ranges (CIDR) allowed to connect to the SSH bastion."
  type        = list(string)
  default     = []
}

variable "enable_smtp" {
  description = "Enable SMTP on the gateway."
  type        = bool
  default     = false
}

variable "gateway_networks" {
  description = "Map of Private Network attachments (GatewayNetworks)."
  type = map(object({
    private_network_id = string
    enable_masquerade  = optional(bool, true)
    push_default_route = optional(bool, true)
  }))
  default = {}
}