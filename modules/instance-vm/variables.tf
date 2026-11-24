variable "name" {
  description = "Name of the instance"
  type        = string
}

variable "instance_type" {
  description = "Commercial type of the server (e.g. DEV1-S, PLAY2-MICRO, PRO2-XXS)"
  type        = string
}

variable "image" {
  description = "UUID or label of the base image (e.g. ubuntu_jammy)"
  type        = string
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

variable "create_instance" {
  description = "Whether to create the instance resource"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to the instance"
  type        = list(string)
  default     = []
}

variable "security_group_id" {
  description = "Security group ID to attach to the instance"
  type        = string
  default     = null
}

variable "placement_group_id" {
  description = "Placement group ID to attach to the instance"
  type        = string
  default     = null
}

variable "enable_dynamic_ip" {
  description = "Whether to attach a dynamic IP"
  type        = bool
  default     = false
}

variable "state" {
  description = "Desired state: started, stopped, or standby"
  type        = string
  default     = "started"
}

variable "boot_type" {
  description = "Boot type: local, bootscript, or rescue"
  type        = string
  default     = "local"
}

variable "protected" {
  description = "Enable server protection option"
  type        = bool
  default     = false
}

variable "ips" {
  description = "Map of reserved IPs to create and attach"
  type = map(object({
    reverse = optional(string)
  }))
  default = {}
}

variable "existing_ip_ids" {
  description = "IDs of existing elastic public IPs (scaleway_instance_ip) to attach. Useful when a stable public IP is created outside the module (e.g. a VPN customer gateway endpoint). Merged with the IPs created from `ips`."
  type        = list(string)
  default     = []
}

variable "root_volume" {
  description = "Root volume configuration"
  type = object({
    size_in_gb            = optional(number)
    volume_type           = optional(string)
    delete_on_termination = optional(bool)
    sbs_iops              = optional(number)
    volume_id             = optional(string)
  })
  default = null
}

variable "additional_volume_ids" {
  description = "List of additional volume IDs to attach"
  type        = list(string)
  default     = []
}

variable "private_networks" {
  description = <<-EOF
    Map of private networks to attach. Each entry may optionally pin a static
    IPv4 on the PN via `ipam_ip` (created as a Scaleway IPAM reservation and
    attached with ipam_ip_ids). When `ipam_ip` is null/absent the NIC uses DHCP
    (current default). Pinning is the durable pattern for any address that the
    factory references by value (e.g. the hub-test FW egress-rule source): a
    static reservation cannot drift across destroys/recreates like a DHCP lease
    can.
  EOF
  type = map(object({
    pn_id   = string
    ipam_ip = optional(string)
  }))
  default = {}
}

variable "user_data" {
  description = "Map of user data / cloud-init configuration"
  type        = map(string)
  default     = {}
}