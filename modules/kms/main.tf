/**
 * KMS Module
 * Creates a Scaleway Key Manager key for customer-managed encryption.
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

resource "scaleway_key_manager_key" "this" {
  name        = var.name
  description = var.description
  project_id  = var.project_id
  region      = var.region
  algorithm   = var.algorithm
  usage       = var.usage
  unprotected = var.unprotected
}
