/**
 * Object Storage Module
 * Creates an S3-compatible bucket with optional lock configuration and SSE.
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

resource "scaleway_object_bucket" "this" {
  name                = var.name
  project_id          = var.project_id
  region              = var.region
  tags                = var.tags
  object_lock_enabled = var.enable_lock
  # Object-locked buckets reject plain DeleteBucket (409) - force_destroy
  # purges GOVERNANCE-locked objects and deletes via the control plane.
  force_destroy = var.force_destroy
}

resource "scaleway_object_bucket_lock_configuration" "this" {
  count      = var.enable_lock ? 1 : 0
  bucket     = scaleway_object_bucket.this.name
  region     = var.region
  project_id = var.project_id

  rule {
    default_retention {
      mode = "GOVERNANCE"
      days = 365
    }
  }
}

resource "scaleway_object_bucket_server_side_encryption_configuration" "this" {
  count      = var.enable_sse ? 1 : 0
  bucket     = scaleway_object_bucket.this.name
  region     = var.region
  project_id = var.project_id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

