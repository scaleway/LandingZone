/**
 * Scaleway Serverless Job Module
 *
 * Wraps `scaleway_job_definition` with the common knobs: image + resources,
 * startup command / args, environment, Secret Manager references, an optional
 * cron trigger and an optional retry policy.
 *
 * Example:
 *   module "state_sync" {
 *     source = "../../modules/serverless-job"
 *     name   = "lz-dev-state-sync"
 *     project_id = "01...?"
 *     image_uri  = "rclone/rclone:latest"
 *     startup_command = ["rclone", "sync", "src:...", "dst:..."]
 *     env = { ... }
 *     secret_references = [ { secret_id = "...", environment = "SCW_SECRET_KEY" } ]
 *     cron_schedule = "0 2 * * *"
 *   }
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
}

resource "scaleway_job_definition" "this" {
  name                   = var.name
  description            = var.description
  project_id             = var.project_id
  region                 = var.region
  cpu_limit              = var.cpu_limit
  memory_limit           = var.memory_limit
  local_storage_capacity = var.local_storage_capacity
  image_uri              = var.image_uri
  startup_command        = var.startup_command
  args                   = var.args
  env                    = var.env
  timeout                = var.timeout

  dynamic "cron" {
    for_each = var.cron_schedule != null ? [1] : []
    content {
      schedule = var.cron_schedule
      timezone = var.cron_timezone
    }
  }

  dynamic "retry_policy" {
    for_each = var.retry_max_retries != null ? [1] : []
    content {
      max_retries = var.retry_max_retries
    }
  }

  dynamic "secret_reference" {
    for_each = var.secret_references
    content {
      secret_id      = secret_reference.value.secret_id
      secret_version = secret_reference.value.secret_version
      environment    = secret_reference.value.environment
      file           = secret_reference.value.file
    }
  }
}
