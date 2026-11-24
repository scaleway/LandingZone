# ---------------------------------------------------------------------------
# Firewall Image Module -- Input Variables
# ---------------------------------------------------------------------------

variable "vendor" {
  description = "Firewall vendor for naming/tagging (opnsense; others may come as add-ons)."
  type        = string
}

variable "appliance_version" {
  description = "Appliance version (e.g. 26.7, 7.4.1, 10.2.0)."
  type        = string
}

variable "project_id" {
  description = "Scaleway project ID."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "zones" {
  description = "Zones to create snapshots in (e.g. ['fr-par-1', 'fr-par-2'])."
  type        = list(string)
}

variable "snapshot_size" {
  description = "Size in GB for each snapshot."
  type        = number
  default     = 25
}

variable "create_volumes" {
  description = "Whether to create SBS volumes from the snapshots (used as instance root volumes). Set false when the caller (stage-3) only owns the golden bucket+snapshots and volumes are derived per-firewall downstream."
  type        = bool
  default     = true
}

variable "snapshot_id_override" {
  description = "When set, skip snapshot creation/import and build volumes from this pre-existing snapshot ID (created by bootstrap's image pipeline). Keeps volume resource addresses identical across image ownership modes."
  type        = string
  default     = ""
}

variable "volume_iops" {
  description = "IOPS for the Scaleway Block Volume created from the snapshot."
  type        = number
  default     = 5000
}

variable "tags" {
  description = "Tags to apply to snapshots."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Image source
# ---------------------------------------------------------------------------

variable "source_url" {
  description = "URL to download the appliance image from. Ignored if local_path is set."
  type        = string
  default     = null
}

variable "source_format" {
  description = "Format of the downloaded/local file: qcow2, raw, bz2, xz, gz, iso, vmdk."
  type        = string
  default     = "raw"
}

variable "local_path" {
  description = "Absolute path to a pre-existing image file on the local machine (skips download)."
  type        = string
  default     = null
}

variable "enable_download" {
  description = "Whether to download + convert the image. Set false if the qcow2 already exists in the bucket."
  type        = bool
  default     = true
}

variable "force_download" {
  description = "Force re-download even if the file already exists in /tmp."
  type        = bool
  default     = false
}

variable "force_upload" {
  description = "Force re-upload even if the object already exists in the bucket."
  type        = bool
  default     = false
}

variable "object_key" {
  description = "Object key (filename) in the bucket. Defaults to '{vendor}-{appliance_version}.qcow2'."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Object storage bucket
# ---------------------------------------------------------------------------

variable "bucket_name" {
  description = "Name of the S3 bucket to upload the QCOW2 to (must be a plain bucket -- no lock/SSE)."
  type        = string
}

variable "s3_endpoint" {
  description = "S3-compatible endpoint URL for Scaleway Object Storage."
  type        = string
  default     = "https://s3.fr-par.scw.cloud"
}

variable "upload_access_key" {
  description = "Access key with S3 write permission on the bucket."
  type        = string
  sensitive   = true
  default     = ""
}

variable "upload_secret_key" {
  description = "Secret key with S3 write permission on the bucket."
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_upload" {
  description = "Whether to run the import script (download/convert/upload). Set false to skip -- e.g. if the object already exists in the bucket."
  type        = bool
  default     = true
}
