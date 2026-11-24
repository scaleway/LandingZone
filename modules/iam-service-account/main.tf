/**
 * Scaleway IAM Service Account Module
 * Creates an IAM Application (service account) and optionally an API key.
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

resource "scaleway_iam_application" "this" {
  name            = var.name
  description     = var.description
  tags            = var.tags
  organization_id = var.organization_id
}

resource "scaleway_iam_api_key" "this" {
  count              = var.create_api_key ? 1 : 0
  application_id     = scaleway_iam_application.this.id
  description        = var.api_key_description
  expires_at         = var.api_key_expires_at
  default_project_id = var.api_key_default_project_id
}
