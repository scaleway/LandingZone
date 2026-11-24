output "backup_application_id" {
  description = "ID of the backup IAM application."
  value       = module.backup_sa.id
}

output "backup_application_name" {
  description = "Name of the backup IAM application."
  value       = module.backup_sa.name
}

output "backup_api_key_id" {
  description = "ID of the backup API key."
  value       = module.backup_sa.api_key_id
}

output "backup_access_key_secret_id" {
  description = "ID of the Secret Manager secret holding the backup access key."
  value       = module.backup_credentials["access_key"].id
}

output "backup_secret_key_secret_id" {
  description = "ID of the Secret Manager secret holding the backup secret key."
  value       = module.backup_credentials["secret_key"].id
}

output "state_sync_job_id" {
  description = "ID of the state -> primary backup copy job definition."
  value       = module.state_sync.id
}

output "state_sync_job_name" {
  description = "Name of the state -> primary backup copy job definition."
  value       = module.state_sync.name
}

output "state_sync_target" {
  description = "Primary backup destination of the state sync (bucket/prefix)."
  value       = "${var.backup_bucket_name}/terraform-state"
}

output "dr_sync_job_id" {
  description = "ID of the full backup -> cross-region DR mirror job definition."
  value       = module.dr_sync.id
}

output "dr_sync_job_name" {
  description = "Name of the full backup -> cross-region DR mirror job definition."
  value       = module.dr_sync.name
}

output "fw_exporter_container_id" {
  description = "ID of the firewall config exporter container."
  value       = module.fw_exporter.id
}

output "fw_exporter_endpoint" {
  description = "Public endpoint of the firewall config exporter (private; invoke with X-Auth-Token of the backup SA)."
  value       = module.fw_exporter.endpoint
}

output "fw_exporter_trigger_id" {
  description = "ID of the cron trigger scheduling the firewall config export."
  value       = module.fw_exporter.trigger_id
}

output "fw_backup_key_secret_id" {
  description = "ID of the Secret Manager secret holding the firewall backup SSH private key."
  value       = module.fw_backup_key_secret.id
}

output "fw_exporter_namespace_id" {
  description = "ID of the serverless namespace hosting the FW exporter (reused by the fw-restore drill probe)."
  value       = module.fw_exporter.namespace_id
}
