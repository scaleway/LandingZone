/**
 * Secrets Module
 * Creates a Scaleway Secret Manager secret and an initial version.
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

resource "scaleway_secret" "this" {
  name        = var.name
  description = var.description
  project_id  = var.project_id
  region      = var.region
  tags        = var.tags
}

resource "scaleway_secret_version" "this" {
  count     = var.secret_value != null ? 1 : 0
  secret_id = scaleway_secret.this.id
  data      = var.secret_value
  region    = var.region
}
