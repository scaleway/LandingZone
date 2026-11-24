/**
 * Scaleway IAM Group Module
 * Creates and manages Scaleway IAM Groups and their memberships.
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

resource "scaleway_iam_group" "this" {
  name            = var.name
  description     = var.description
  tags            = var.tags
  application_ids = var.application_ids
  user_ids        = var.user_ids
  organization_id = var.organization_id
}
