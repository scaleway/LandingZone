# ---------------------------------------------------------------------------
# Firewall Image Module, vendor-agnostic QCOW2 => snapshot pipeline.
#
# Downloads/imports any firewall vendor image (OPNsense, FortiGate, ...) into
# SBS snapshots (one per zone), optionally creating block volumes from them.
# Outputs a snapshot_ids map ready for modules/ha-firewall.
# ---------------------------------------------------------------------------

terraform {
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

locals {
  qcow_filename = coalesce(var.object_key, "${var.vendor}-${var.appliance_version}.qcow2")
  script_path   = abspath("${path.module}/scripts/import-firewall-image.sh")
}

# ---------------------------------------------------------------------------
# 1. Download + convert + upload (invokes the standalone shell script)
# ---------------------------------------------------------------------------
resource "null_resource" "import_image" {
  count = var.enable_upload ? 1 : 0

  triggers = {
    vendor       = var.vendor
    version      = var.appliance_version
    src_url      = var.source_url != null ? var.source_url : ""
    src_path     = var.local_path != null ? var.local_path : ""
    src_format   = var.source_format
    object_key   = local.qcow_filename
    bucket       = var.bucket_name
    s3_endpoint  = var.s3_endpoint
    force_upload = var.force_upload ? "yes" : "no"
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      "${local.script_path}" \
        ${var.local_path != null ? "--src-path \"${var.local_path}\"" : "--src-url \"${var.source_url}\""} \
        --src-format "${var.source_format}" \
        --obj-key "${local.qcow_filename}" \
        --bucket "${var.bucket_name}" \
        --endpoint "${var.s3_endpoint}" \
        --access-key "${var.upload_access_key}" \
        --secret-key "${var.upload_secret_key}" \
        --region "${var.region}" \
        ${var.force_download ? "--force-download" : ""} \
        ${var.force_upload ? "--force-upload" : ""}
    EOT
  }
}

# ---------------------------------------------------------------------------
# 2. Import the QCOW2 object as SBS snapshots, one per zone. With
#    snapshot_id_override a pre-existing (golden) snapshot is used instead and
#    only volumes are derived from it. project_id is explicit because block
#    volumes can only be created from a snapshot in the same project.
# ---------------------------------------------------------------------------
resource "scaleway_block_snapshot" "this" {
  for_each = var.snapshot_id_override != "" ? toset([]) : toset(var.zones)

  name       = "${var.vendor}-${var.appliance_version}-snap${index(var.zones, each.key) + 1}"
  zone       = each.key
  project_id = var.project_id
  tags       = concat(var.tags, [var.vendor, "image"])

  import {
    bucket = var.bucket_name
    key    = local.qcow_filename
  }

  depends_on = [null_resource.import_image]
}

# ---------------------------------------------------------------------------
# 3. SBS volumes from the snapshots (used as instance root volumes). With
#    create_volumes=false the caller owns bucket + snapshots and volumes are
#    derived downstream by modules/firewall.
# ---------------------------------------------------------------------------
resource "scaleway_block_volume" "this" {
  for_each = var.create_volumes ? toset(var.zones) : toset([])

  name        = "${var.vendor}-${var.appliance_version}-vol${index(var.zones, each.key) + 1}"
  size_in_gb  = var.snapshot_size
  iops        = var.volume_iops
  zone        = each.key
  project_id  = var.project_id
  snapshot_id = var.snapshot_id_override != "" ? var.snapshot_id_override : scaleway_block_snapshot.this[each.key].id
  tags        = concat(var.tags, ["stage3", var.vendor, "image"])

  depends_on = [scaleway_block_snapshot.this]
}
