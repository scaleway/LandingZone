/**
 * Scaleway Serverless Function Module
 *
 * Wraps `scaleway_function_namespace` + `scaleway_function` with the common
 * knobs: runtime + handler, zip source, resources/scale, environment + secret
 * environment variables, optional Private Network attachment.
 *
 * The namespace is created alongside by default; pass `namespace_id` (with
 * `create_namespace = false`) to reuse an existing one.
 *
 * Example:
 *   module "exporter" {
 *     source      = "../../modules/serverless-function"
 *     name        = "lz-dev-pruner"
 *     project_id  = "..."
 *     region      = "fr-par"
 *     runtime     = "python311"
 *     handler     = "main.prune"
 *     privacy     = "private"
 *     environment_variables = { "BUCKET" = "lz-dev-backup" }
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

locals {
  namespace_id = var.namespace_id != null ? var.namespace_id : scaleway_function_namespace.this[0].id
}

resource "scaleway_function_namespace" "this" {
  count       = var.create_namespace && var.namespace_id == null ? 1 : 0
  name        = var.namespace_name != null ? var.namespace_name : var.name
  description = var.description
  project_id  = var.project_id
  region      = var.region
}

resource "scaleway_function" "this" {
  name                         = var.name
  description                  = var.description
  namespace_id                 = local.namespace_id
  project_id                   = var.project_id
  region                       = var.region
  tags                         = var.tags
  runtime                      = var.runtime
  handler                      = var.handler
  privacy                      = var.privacy
  zip_file                     = var.zip_file
  zip_hash                     = var.zip_hash
  deploy                       = var.deploy
  min_scale                    = var.min_scale
  max_scale                    = var.max_scale
  memory_limit                 = var.memory_limit
  timeout                      = var.timeout
  environment_variables        = var.environment_variables
  secret_environment_variables = var.secret_environment_variables
  private_network_id           = var.private_network_id
  http_option                  = var.http_option
}
