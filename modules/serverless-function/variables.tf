variable "name" {
  description = "Name of the Serverless Function."
  type        = string
}

variable "description" {
  description = "Description of the function (and of the namespace it creates)."
  type        = string
  default     = null
}

variable "project_id" {
  description = "Scaleway Project ID the function belongs to."
  type        = string
}

variable "region" {
  description = "Scaleway region of the function."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags applied to the function."
  type        = list(string)
  default     = []
}

# --- namespace handling -----------------------------------------------------
variable "create_namespace" {
  description = "Create the function namespace (default). Set false to reuse an existing one via namespace_id."
  type        = bool
  default     = true
}

variable "namespace_id" {
  description = "ID of an existing namespace. When set, no namespace is created and namespace_name is ignored."
  type        = string
  default     = null
}

variable "namespace_name" {
  description = "Name of the namespace to create. Defaults to the function name."
  type        = string
  default     = null
}

# --- runtime -------------------------------------------------------------------
variable "runtime" {
  description = "Runtime of the function (e.g. python311, node20). See Scaleway docs for supported runtimes."
  type        = string
}

variable "handler" {
  description = "Handler of the function (depends on the runtime, e.g. 'handler.handle')."
  type        = string
}

variable "privacy" {
  description = "Privacy of the function: private or public."
  type        = string
  default     = "private"
}

variable "zip_file" {
  description = "Path to a zip file containing the function sources."
  type        = string
  default     = null
}

variable "zip_hash" {
  description = "Hash of the zip file (used to detect source changes)."
  type        = string
  default     = null
}

variable "deploy" {
  description = "Whether to deploy on apply."
  type        = bool
  default     = null
}

# --- scale / resources ----------------------------------------------------------
variable "min_scale" {
  description = "Minimum number of instances (billed continuously once > 0)."
  type        = number
  default     = null
}

variable "max_scale" {
  description = "Maximum number of instances."
  type        = number
  default     = null
}

variable "memory_limit" {
  description = "Memory limit in MiB."
  type        = number
  default     = null
}

variable "timeout" {
  description = "Function timeout (Go duration, e.g. '30s')."
  type        = string
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

# --- network ---------------------------------------------------------------------
variable "private_network_id" {
  description = "Private Network to attach the function to."
  type        = string
  default     = null
}

variable "http_option" {
  description = "HTTP option (e.g. 'redirected' for redirect to HTTPS)."
  type        = string
  default     = null
}
