output "project_id" {
  description = "ID of the infra-ops project."
  value       = scaleway_account_project.infra_ops.id
}

output "project_name" {
  description = "Name of the infra-ops project."
  value       = scaleway_account_project.infra_ops.name
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = scaleway_object_bucket.terraform_state.name
}

output "bucket_suffix" {
  description = "Frozen creation timestamp shared by every bootstrap-named bucket as the final name segment (<prefix>-<env>-<purpose>-<suffix>)."
  value       = local.bucket_suffix
}

output "state_bucket_id" {
  description = "ID of the Terraform state bucket."
  value       = scaleway_object_bucket.terraform_state.id
}

output "bootstrap_application_id" {
  description = "ID of the bootstrap IAM application."
  value       = scaleway_iam_application.bootstrap.id
}

output "bootstrap_application_name" {
  description = "Name of the bootstrap IAM application."
  value       = scaleway_iam_application.bootstrap.name
}

output "bootstrap_api_key_id" {
  description = "ID of the bootstrap API key."
  value       = scaleway_iam_api_key.bootstrap.id
}

output "bootstrap_access_key" {
  description = "Access key for the bootstrap service account."
  value       = scaleway_iam_api_key.bootstrap.access_key
  sensitive   = true
}

output "bootstrap_secret_key" {
  description = "Secret key for the bootstrap service account."
  value       = scaleway_iam_api_key.bootstrap.secret_key
  sensitive   = true
}

output "bootstrap_policy_id" {
  description = "ID of the bootstrap IAM policy."
  value       = scaleway_iam_policy.bootstrap.id
}

output "state_endpoint" {
  description = "S3-compatible endpoint for the state bucket."
  value       = "https://s3.${var.region}.scw.cloud"
}

# ---------------------------------------------------------------------------
# The backup stack lives in stage 5 and the golden firewall image pipeline in
# stage 3 - bootstrap owns only the infra-ops project, the state bucket and
# the bootstrap SA/key.
# ---------------------------------------------------------------------------