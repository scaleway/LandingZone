/**
 * Object Storage Module
 * Creates an S3-compatible bucket with optional lock configuration and SSE,
 * plus an optional generic local-exec lifecycle hook (e.g. a destructor gate
 * that empties the bucket before destroy - terraform refuses to delete a
 * non-empty bucket with 409).
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

  # Create-time hook (var references are allowed here). No-op "true" when
  # disabled - provisioner blocks cannot be made conditional.
  provisioner "local-exec" {
    when        = create
    interpreter = var.provisioner != null ? var.provisioner.interpreter : ["bash", "-c"]
    environment = var.provisioner != null ? var.provisioner.environment : {}
    command     = var.provisioner != null && var.provisioner.on_create ? var.provisioner.command : "true"
  }
}

# Destroy-time hook. Terraform forbids variable references inside destroy-time
# provisioners, so the script + bucket facts are captured at apply time on a
# companion terraform_data (read back via self.input at destroy) and the
# depends_on guarantees it runs before the bucket itself is deleted.
resource "terraform_data" "destroy_provisioner" {
  count = var.provisioner != null && var.provisioner.on_destroy ? 1 : 0

  input = {
    command     = var.provisioner.command
    bucket_name = scaleway_object_bucket.this.name
    region      = scaleway_object_bucket.this.region
    endpoint    = "https://s3.${scaleway_object_bucket.this.region}.scw.cloud"
  }

  depends_on = [scaleway_object_bucket.this]

  provisioner "local-exec" {
    when = destroy

    command = <<-EOT
      set -euo pipefail
      export BUCKET='${self.input["bucket_name"]}'
      export REGION='${self.input["region"]}'
      export ENDPOINT='${self.input["endpoint"]}'
      ${self.input["command"]}
    EOT
  }
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
