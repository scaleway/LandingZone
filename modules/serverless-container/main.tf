/**
 * Scaleway Serverless Container Module
 *
 * Wraps `scaleway_container_namespace` + `scaleway_container` with the common
 * knobs: image, resources, scale, environment + secret environment variables,
 * optional Private Network attachment (hub LAN PN for egress via the FWs), and
 * optional HTTP options.
 *
 * The namespace is created alongside by default; pass `namespace_id` (with
 * `create_namespace = false`) to reuse an existing one.
 *
 * Example (private-network-attached container):
 *   module "exporter" {
 *     source         = "../../modules/serverless-container"
 *     name           = "lz-dev-fw-export"
 *     project_id     = "..."
 *     region         = "fr-par"
 *     image          = "rg.fr-par.scw.cloud/ns/export:1.0.0"
 *     port           = 8080
 *     privacy        = "private"
 *     private_network_id = "11111111-1111-1111-1111-111111111111"
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
  namespace_id = var.namespace_id != null ? var.namespace_id : scaleway_container_namespace.this[0].id
}

resource "scaleway_container_namespace" "this" {
  count       = var.create_namespace && var.namespace_id == null ? 1 : 0
  name        = var.namespace_name != null ? var.namespace_name : var.name
  description = var.description
  project_id  = var.project_id
  region      = var.region
}

resource "scaleway_container" "this" {
  name                         = var.name
  description                  = var.description
  namespace_id                 = local.namespace_id
  region                       = var.region
  tags                         = var.tags
  image                        = var.image
  registry_image               = var.registry_image
  port                         = var.port
  protocol                     = var.protocol
  privacy                      = var.privacy
  min_scale                    = var.min_scale
  max_scale                    = var.max_scale
  cpu_limit                    = var.cpu_limit
  memory_limit                 = var.memory_limit
  local_storage_limit_bytes    = var.local_storage_limit_bytes
  timeout                      = var.timeout
  deploy                       = var.deploy
  environment_variables        = var.environment_variables
  secret_environment_variables = var.secret_environment_variables
  private_network_id           = var.private_network_id
  https_connections_only       = var.https_connections_only
  http_option                  = var.http_option
  command                      = var.command
  args                         = var.args
}

resource "scaleway_container_trigger" "cron" {
  count        = var.cron_schedule != null ? 1 : 0
  name         = "${var.name}-cron"
  description  = "Scheduled invocation of ${var.name}"
  container_id = scaleway_container.this.id
  region       = var.region
  tags         = var.tags

  destination_config {
    http_path   = var.cron_http_path
    http_method = var.cron_http_method
  }

  cron {
    schedule = var.cron_schedule
    timezone = var.cron_timezone
    body     = var.cron_body
  }
}
