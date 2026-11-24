variable "name" {
  description = "Name of the Serverless Container."
  type        = string
}

variable "description" {
  description = "Description of the container (and of the namespace it creates)."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway Project ID the container belongs to (applied to the namespace; the container inherits it)."
  type        = string
}

variable "region" {
  description = "Scaleway region of the container."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags applied to the container."
  type        = list(string)
  default     = []
}

# --- namespace handling -----------------------------------------------------
variable "create_namespace" {
  description = "Create the container namespace (default). Set false to reuse an existing one via namespace_id."
  type        = bool
  default     = true
}

variable "namespace_id" {
  description = "ID of an existing namespace. When set, no namespace is created and namespace_name is ignored."
  type        = string
  default     = null
}

variable "namespace_name" {
  description = "Name of the namespace to create. Defaults to the container name."
  type        = string
  default     = null
}

# --- image / runtime ---------------------------------------------------------
variable "image" {
  description = "Image to deploy (registry endpoint form, e.g. rg.fr-par.scw.cloud/ns/img:tag)."
  type        = string
  default     = null
}

variable "registry_image" {
  description = "Alternative image reference. Only one of `image` / `registry_image` should be set."
  type        = string
  default     = null
}

variable "port" {
  description = "HTTP port of the container (exposed internally)."
  type        = number
  default     = null
}

variable "protocol" {
  description = "Communication protocol: http1 or h2c."
  type        = string
  default     = null
}

variable "privacy" {
  description = "Privacy of the container: private or public."
  type        = string
  default     = null
}

# --- scale / resources --------------------------------------------------------
variable "min_scale" {
  description = "Minimum number of instances."
  type        = number
  default     = null
}

variable "max_scale" {
  description = "Maximum number of instances."
  type        = number
  default     = null
}

variable "cpu_limit" {
  description = "CPU limit in mCPU."
  type        = number
  default     = null
}

variable "memory_limit" {
  description = "Memory limit in MiB."
  type        = number
  default     = null
}

variable "local_storage_limit_bytes" {
  description = "Local storage limit in bytes (non-deprecated field)."
  type        = number
  default     = null
}

variable "timeout" {
  description = "Container request timeout in SECONDS (number). Default is 300. (Note: unlike job timeouts, this is seconds, not a Go duration.)"
  type        = number
  default     = null
}

variable "deploy" {
  description = "Whether to deploy on apply. Useful to disable while wiring config."
  type        = bool
  default     = null
}

# --- environment ---------------------------------------------------------------
variable "environment_variables" {
  description = "Plain environment variables."
  type        = map(string)
  default     = {}
}

variable "secret_environment_variables" {
  description = "Secret environment variables (map of var name -> secret reference/value). Sensitive."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# --- network -------------------------------------------------------------------
variable "private_network_id" {
  description = "Private Network to attach the container to (e.g. the hub LAN PN)."
  type        = string
  default     = null
}

variable "https_connections_only" {
  description = "Only allow HTTPS connections."
  type        = bool
  default     = null
}

variable "http_option" {
  description = "HTTP option (e.g. 'redirected' for redirect to HTTPS)."
  type        = string
  default     = null
}

# --- command --------------------------------------------------------------------
variable "command" {
  description = "Startup command override (list). Empty = image default."
  type        = list(string)
  default     = []
}

variable "args" {
  description = "Arguments override (list)."
  type        = list(string)
  default     = []
}

# --- cron trigger -------------------------------------------------------------
variable "cron_schedule" {
  description = "UNIX cron schedule to invoke the container via a trigger (e.g. '30 2 * * *'). Null = no cron trigger."
  type        = string
  default     = null
}

variable "cron_timezone" {
  description = "Timezone for the cron trigger schedule in tz database format (e.g. 'UTC')."
  type        = string
  default     = "UTC"
}

variable "cron_http_path" {
  description = "HTTP path the cron trigger invokes on the container (e.g. '/')."
  type        = string
  default     = "/"
}

variable "cron_http_method" {
  description = "HTTP method the cron trigger uses (get, post, put, patch, delete)."
  type        = string
  default     = "post"
}

variable "cron_body" {
  description = "Optional request body the cron trigger sends to the container."
  type        = string
  default     = null
}
