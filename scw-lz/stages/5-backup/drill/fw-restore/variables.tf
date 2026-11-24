variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

variable "infra_ops_project_id" {
  description = "ID of the infra-ops project (drill scaffold + container namespace)."
  type        = string
}

variable "region" {
  description = "Scaleway region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Default Scaleway zone (provider default; nodes are pinned per node)."
  type        = string
  default     = "fr-par-2"
}

variable "environment" {
  description = "Environment name (dev, prod). Used for naming."
  type        = string
  default     = "dev"
}

variable "state_bucket" {
  description = "State bucket name (for the stage-3 remote state data source)."
  type        = string
}

variable "state_endpoint" {
  description = "S3-compatible endpoint of the state bucket."
  type        = string
}

variable "state_access_key" {
  description = "Access key for reading prior stages' remote state."
  type        = string
  sensitive   = true
}

variable "state_secret_key" {
  description = "Secret key for reading prior stages' remote state."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Drill-specific
# ---------------------------------------------------------------------------

variable "drill_zone_fw_passive" {
  description = "Zone of the drill fw-passive node (must mirror production so the restored config's CARP/advskew assumptions hold)."
  type        = string
  default     = "fr-par-1"
}

variable "drill_zone_fw_active" {
  description = "Zone of the drill fw-active node (designated CARP master, fr-par-2)."
  type        = string
  default     = "fr-par-2"
}

variable "fw_instance_type" {
  description = "Instance type for the restored firewall nodes (same as production)."
  type        = string
  default     = "POP2-2C-8G"
}

variable "fw_snapshot_size" {
  description = "Size in GB of the drill boot volumes (same as production)."
  type        = number
  default     = 25
}

variable "restore_fw_passive_xml_file" {
  description = "Path to the DR-restored passive config XML (gitignored). Empty = ./restore/fw_passive.xml."
  type        = string
  default     = ""
}

variable "restore_fw_active_xml_file" {
  description = "Path to the DR-restored active config XML (gitignored). Empty = ./restore/fw_active.xml."
  type        = string
  default     = ""
}

variable "probe_namespace_id" {
  description = "Existing serverless container namespace to host the drill probe. Empty = reuse the stage-5 FW exporter namespace (auto-resolved from stage-5 remote state)."
  type        = string
  default     = ""
}

variable "fw_backup_key_file" {
  description = "Path to the firewall backup SSH private key (gitignored). Empty = scw-lz/keys-<env>/fw-backup/id_ed25519."
  type        = string
  default     = ""
}
