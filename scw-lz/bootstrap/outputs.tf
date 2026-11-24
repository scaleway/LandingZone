output "infra_ops_project_id" {
  description = "ID of the infra-ops project created for bootstrap."
  value       = module.bootstrap.project_id
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = module.bootstrap.state_bucket_name
}

output "state_endpoint" {
  description = "S3-compatible endpoint for the state bucket."
  value       = module.bootstrap.state_endpoint
}

output "bootstrap_application_id" {
  description = "ID of the bootstrap IAM application."
  value       = module.bootstrap.bootstrap_application_id
}

output "bootstrap_application_name" {
  description = "Name of the bootstrap IAM application."
  value       = module.bootstrap.bootstrap_application_name
}

output "bootstrap_api_key_id" {
  description = "ID of the bootstrap API key."
  value       = module.bootstrap.bootstrap_api_key_id
}

output "bootstrap_access_key" {
  description = "Access key for the bootstrap service account (sensitive)."
  value       = module.bootstrap.bootstrap_access_key
  sensitive   = true
}

output "bootstrap_secret_key" {
  description = "Secret key for the bootstrap service account (sensitive)."
  value       = module.bootstrap.bootstrap_secret_key
  sensitive   = true
}

output "bootstrap_credentials_secret_id" {
  description = "ID of the Secret Manager secret containing bootstrap credentials."
  value       = scaleway_secret.bootstrap_credentials.id
}

output "backend_config_file" {
  description = "Path to the generated per-env backend config file for other stages."
  value       = abspath("${path.module}/../envs/${var.environment}/backend-${var.environment}.tfvars")
}

output "providers_config_file" {
  description = "Path to the generated per-env providers config file for other stages."
  value       = abspath("${path.module}/../envs/${var.environment}/providers-${var.environment}.tfvars")
}

# ---------------------------------------------------------------------------
# Org-setup outputs. Stages 1-6 read these through
# data.terraform_remote_state.bootstrap (local backend via stage0_state_path).
# ---------------------------------------------------------------------------

output "organization_id" {
  description = "Scaleway Organization ID."
  value       = var.organization_id
}

output "environment" {
  description = "Environment name (e.g., dev, prod)."
  value       = var.environment
}

output "bucket_suffix" {
  description = "Frozen creation timestamp appended to every bootstrap-named bucket (<prefix>-<env>-<purpose>-<suffix>). Stages building their own bucket names (e.g. stage-3 image-import) reuse it to stay consistent and collision-free."
  value       = module.bootstrap.bucket_suffix
}

output "project_ids" {
  description = "Map of created project IDs (project key -> id; the key equal to the environment name is the <project_prefix>-<env> project)."
  value       = { for k, v in module.projects : k => v.id }
}

output "iam_group_ids" {
  description = "Map of created IAM group IDs."
  value       = { for k, v in module.iam_groups : k => v.id }
}

output "service_account_ids" {
  description = "Map of created service account (application) IDs."
  value       = { for k, v in module.service_accounts : k => v.id }
}

output "ssh_key_ids" {
  description = "Map of created SSH key IDs."
  value       = { for k, v in scaleway_iam_ssh_key.keys : k => v.id }
}

output "ssh_private_keys" {
  description = "Map of generated SSH private keys (sensitive). Save these securely!"
  value       = { for k, v in tls_private_key.keys : k => v.private_key_pem }
  sensitive   = true
}

output "kms_key_ids" {
  description = "Map of created KMS key IDs."
  value       = { for k, v in module.kms_keys : k => v.id }
}

output "audit_log_bucket_names" {
  description = "Map of created audit log bucket names."
  value       = { for k, v in module.audit_log_buckets : k => v.name }
}

output "secret_ids" {
  description = "Map of created Secret Manager secret IDs."
  value       = { for k, v in module.secrets : k => v.id }
}

output "iam_policy_ids" {
  description = "Map of created IAM policy IDs."
  value       = module.iam_policies.ids
}

output "iam_policy_names" {
  description = "Map of created IAM policy names."
  value       = module.iam_policies.names
}

output "ssh_public_keys" {
  description = "Map of generated SSH public keys (OpenSSH format)."
  value       = { for k, v in tls_private_key.keys : k => v.public_key_openssh }
}

output "sso" {
  description = "SSO (SAML/SCIM) configuration summary per sso key - SP metadata the IdP side needs (sp_entity_id, acs_url)."
  value = {
    for k, v in module.sso : k => {
      saml_id      = v.saml_id
      saml_status  = v.saml_status
      sp_entity_id = v.sp_entity_id
      acs_url      = v.acs_url
      scim_id      = v.scim_id
    }
  }
}

output "sso_scim_tokens" {
  description = "SCIM bearer tokens per sso key (sensitive - for IdP provisioning config)."
  value       = { for k, v in module.sso : k => v.scim_bearer_token }
  sensitive   = true
}
