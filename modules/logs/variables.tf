variable "project_id" {
  description = "The ID of the Project the Cockpit resources are associated with."
  type        = string
}

variable "region" {
  description = "The region where the Cockpit resources are located."
  type        = string
  default     = "fr-par"
}

variable "sources" {
  description = "Map of Cockpit data sources to create."
  type = map(object({
    name           = string
    type           = string
    retention_days = number
  }))
  default = {}
}

variable "tokens" {
  description = "Map of Cockpit tokens to create."
  type = map(object({
    name = string
    scopes = optional(object({
      query_metrics       = optional(bool, false)
      write_metrics       = optional(bool, true)
      setup_metrics_rules = optional(bool, false)
      query_logs          = optional(bool, false)
      write_logs          = optional(bool, true)
      setup_logs_rules    = optional(bool, false)
      setup_alerts        = optional(bool, false)
      query_traces        = optional(bool, false)
      write_traces        = optional(bool, false)
    }))
  }))
  default = {}
}