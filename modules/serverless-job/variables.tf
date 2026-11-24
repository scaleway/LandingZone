variable "name" {
  description = "Name of the Serverless Job definition."
  type        = string
}

variable "description" {
  description = "Description of the job."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway Project ID the job belongs to."
  type        = string
}

variable "region" {
  description = "Scaleway region of the job."
  type        = string
  default     = "fr-par"
}

variable "image_uri" {
  description = "Container image URI to run (e.g. rclone/rclone:latest)."
  type        = string
}

variable "cpu_limit" {
  description = "CPU limit of the job in mCPU."
  type        = number
  default     = 140
}

variable "memory_limit" {
  description = "Memory limit of the job in MiB."
  type        = number
  default     = 256
}

variable "local_storage_capacity" {
  description = "Local storage capacity of the job in MiB (Scaleway accepts 1000-10240)."
  type        = number
  default     = 1000
}

variable "startup_command" {
  description = "Command to run as a list (overrides the image default). Empty = image default."
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Arguments passed to the command (overrides the image default)."
  type        = list(string)
  default     = []
}

variable "env" {
  description = "Plain environment variables passed to the job."
  type        = map(string)
  default     = {}
}

variable "timeout" {
  description = "Job timeout as a Go duration (e.g. '10m'). Null = provider default."
  type        = string
  default     = null
}

variable "cron_schedule" {
  description = "UNIX cron schedule to run the job (e.g. '0 2 * * *'). Null disables the cron trigger."
  type        = string
  default     = null
}

variable "cron_timezone" {
  description = "Timezone for the cron schedule in tz database format (e.g. 'UTC')."
  type        = string
  default     = "UTC"
}

variable "retry_max_retries" {
  description = "Maximum number of retries upon job failure. Null disables the retry policy."
  type        = number
  default     = null
}

variable "secret_references" {
  description = "Secret Manager references to mount into the job (as env vars or files)."
  type = list(object({
    secret_id      = string
    secret_version = optional(string, "latest")
    environment    = optional(string)
    file           = optional(string)
  }))
  default = []
}
