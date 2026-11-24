variable "project_id" {
  description = "The ID of the Project associated with the DNS zones."
  type        = string
}

variable "zones" {
  description = "Map of DNS zones to create."
  type = map(object({
    domain    = string
    subdomain = string
  }))
  default = {}
}

variable "records" {
  description = "Map of DNS records to create."
  type = map(object({
    zone_key = string
    name     = string
    type     = string
    data     = string
    ttl      = optional(number, 3600)
    priority = optional(number, 0)
  }))
  default = {}
}