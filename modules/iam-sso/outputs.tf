output "saml_id" {
  description = "ID of the organization SAML configuration (null when disabled)."
  value       = var.enabled ? scaleway_iam_saml.main["main"].id : null
}

output "saml_status" {
  description = "Status of the organization SAML configuration (null when disabled)."
  value       = var.enabled ? scaleway_iam_saml.main["main"].status : null
}

output "sp_entity_id" {
  description = "Service Provider entity ID - register this on the IdP side (Authentik provider / Entra enterprise app)."
  value       = var.enabled ? scaleway_iam_saml.main["main"].service_provider.entity_id : null
}

output "acs_url" {
  description = "Assertion Consumer Service (ACS) URL - register this on the IdP side."
  value       = var.enabled ? scaleway_iam_saml.main["main"].service_provider.assertion_consumer_service_url : null
}

output "idp_entity_id" {
  description = "Configured IdP entity ID (as set by the update action)."
  value       = var.enabled ? scaleway_iam_saml.main["main"].entity_id : null
}

output "idp_single_sign_on_url" {
  description = "Configured IdP Single Sign-On URL (as set by the update action)."
  value       = var.enabled ? scaleway_iam_saml.main["main"].single_sign_on_url : null
}

output "saml_certificate_ids" {
  description = "IDs of the attached IdP signing certificates (empty map when disabled)."
  value       = { for k, v in scaleway_iam_saml_certificate.main : k => v.id }
}

output "scim_id" {
  description = "ID of the organization SCIM configuration (null when SCIM disabled)."
  value       = var.enabled && var.enable_scim ? scaleway_iam_scim.main["main"].id : null
}

output "scim_bearer_token" {
  description = "SCIM bearer token for the IdP provisioning endpoint (sensitive - mirror to Secret Manager via data_wo)."
  value       = var.enabled && var.enable_scim ? scaleway_iam_scim_token.main["main"].bearer_token : null
  sensitive   = true
}
