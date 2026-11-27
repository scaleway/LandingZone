variable "name" {

  description = "Name of the bucket."
  type        = string
}

variable "project_id" {
  description = "Scaleway Project ID for the bucket."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "tags" {
  description = "Tags to apply to the bucket."
  type        = map(string)
  default     = {}
}

variable "enable_lock" {
  description = "Enable object lock (WORM) for the bucket."
  type        = bool
  default     = false
}

variable "enable_sse" {
  description = "Enable server-side encryption (SSE-AES256) for the bucket."
  type        = bool
  default     = true
}

variable "force_destroy" {
  description = "Purge all objects and delete the bucket even with Object Lock (replacement-safe)."
  type        = bool
  default     = false
}

variable "provisioner" {
  description = <<-EOF
    Optional local-exec hook for lifecycle actions on the bucket. Leave null
    (default) for no hooks.

    - command: arbitrary bash script. On destroy it runs with BUCKET / REGION /
      ENDPOINT (the bucket's S3 endpoint) exported, so it can empty the bucket
      before deletion (terraform refuses to delete a non-empty bucket - 409),
      or do anything else.
    - on_create: also run at apply time (plain create-time provisioner).
    - on_destroy: run before the bucket is destroyed. Terraform forbids
      variable references inside destroy-time provisioners, so the module
      materializes this hook on a companion terraform_data resource and feeds
      the script through its self.input - fully generic, no size limits, no
      state/tag encoding tricks.
    - interpreter / environment: only used for the create-time run.
  EOF
  type = object({
    command     = string
    on_create   = optional(bool, false)
    on_destroy  = optional(bool, false)
    interpreter = optional(list(string), ["bash", "-c"])
    environment = optional(map(string), {})
  })
  default = null
}
