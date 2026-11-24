variable "name" {
  description = "Name of the Load Balancer"
  type        = string
}

variable "description" {
  description = "Description of the Load Balancer"
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

variable "create_lb" {
  description = "Whether to create the Load Balancer resource"
  type        = bool
  default     = true
}

variable "type" {
  description = "Load Balancer type (e.g. LB-S, LB-M, LB-L)"
  type        = string
  default     = "LB-S"
}

variable "tags" {
  description = "Tags to apply to the Load Balancer"
  type        = list(string)
  default     = []
}

variable "assign_flexible_ip" {
  description = "Whether to automatically assign a flexible public IPv4"
  type        = bool
  default     = false
}

variable "assign_flexible_ipv6" {
  description = "Whether to automatically assign a flexible public IPv6"
  type        = bool
  default     = false
}

variable "ssl_compatibility_level" {
  description = "Enforces minimal SSL version"
  type        = string
  default     = null
}

variable "ips" {
  description = <<EOT
Map of Load Balancer IPs to create.
Use "ipv4" and/or "ipv6" keys.
EOT
  type = map(object({
    is_ipv6 = optional(bool)
    reverse = optional(string)
  }))
  default = {}
}

variable "private_networks" {
  description = "Map of private networks to attach to the Load Balancer"
  type = map(object({
    private_network_id = string
    ipam_ids           = optional(list(string), [])
  }))
  default = {}
}

variable "backends" {
  description = "Map of backends to create"
  type = map(object({
    name                         = optional(string)
    forward_protocol             = string
    forward_port                 = number
    forward_port_algorithm       = optional(string)
    sticky_sessions              = optional(string)
    sticky_sessions_cookie_name  = optional(string)
    server_ips                   = optional(list(string), [])
    proxy_protocol               = optional(string)
    timeout_server               = optional(string)
    timeout_connect              = optional(string)
    timeout_tunnel               = optional(string)
    failover_host                = optional(string)
    ssl_bridging                 = optional(bool)
    ignore_ssl_server_verify     = optional(bool)
    max_connections              = optional(number)
    timeout_queue                = optional(string)
    redispatch_attempt_count     = optional(number)
    max_retries                  = optional(number)
    health_check_timeout         = optional(string)
    health_check_delay           = optional(string)
    health_check_port            = optional(number)
    health_check_max_retries     = optional(number)
    on_marked_down_action        = optional(string)
    health_check_transient_delay = optional(string)
    health_check_send_proxy      = optional(bool)
    health_check_tcp             = optional(bool)
    health_check_http = optional(object({
      uri         = string
      method      = optional(string)
      code        = optional(number)
      host_header = optional(string)
    }))
    health_check_https = optional(object({
      uri         = string
      method      = optional(string)
      code        = optional(number)
      host_header = optional(string)
      sni         = optional(string)
    }))
  }))
  default = {}
}

variable "frontends" {
  description = "Map of frontends to create"
  type = map(object({
    name                  = optional(string)
    backend_key           = string
    inbound_port          = number
    timeout_client        = optional(string)
    certificate_ids       = optional(list(string), [])
    enable_http3          = optional(bool)
    connection_rate_limit = optional(number)
    enable_access_logs    = optional(bool)
  }))
  default = {}
}

variable "acls" {
  description = <<EOT
Map of ACLs to create. Provides WAF-like filtering (IP blocking, path-based rules, redirects).
ACLs are evaluated in ascending order by index.
EOT
  type = map(object({
    name         = optional(string)
    description  = optional(string)
    frontend_key = string
    index        = number
    action = object({
      type = string
      redirect = optional(object({
        type   = string
        target = optional(string)
        code   = optional(number)
      }))
    })
    match = object({
      ip_subnet          = optional(list(string), [])
      ips_edge_services  = optional(bool)
      http_filter        = optional(string)
      http_filter_value  = optional(list(string))
      http_filter_option = optional(string)
      invert             = optional(bool)
    })
  }))
  default = {}
}