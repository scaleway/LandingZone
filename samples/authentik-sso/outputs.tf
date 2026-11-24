output "public_ip" {
  description = "Instance public IPv4 (point your IdP DNS record here)."
  value       = var.enable_public_ip ? module.authentik.public_ips[0].address : null
}

output "url" {
  description = "IdP URL (FQDN). Requires DNS -> public_ip and a trusted cert for browsers."
  value       = "https://${var.authentik_fqdn}"
}

output "url_by_ip" {
  description = "IdP URL reachable immediately by IP (Authentik serves its own self-signed TLS on 443)."
  value       = var.enable_public_ip ? "https://${module.authentik.public_ips[0].address}" : null
}

output "instance_id" {
  description = "Instance ID (for serial console / lifecycle)."
  value       = module.authentik.id
}

# --- The IdP-side values to feed back into bootstrap's `sso:` block ---------
output "idp_entity_id" {
  description = "Authentik IdP Entity ID - set as bootstrap sso.<key>.entity_id."
  value       = local.idp_entity_id
}

output "idp_sso_url" {
  description = "Authentik IdP Single Sign-On URL - set as bootstrap sso.<key>.single_sign_on_url."
  value       = local.idp_sso_url
}

# --- The SCW SP metadata to register inside Authentik (manual/script) ------
output "scw_sp_entity_id" {
  description = "Scaleway SP Entity ID - register in Authentik (SAML provider issuer). From bootstrap output."
  value       = var.sp_entity_id
}

output "scw_acs_url" {
  description = "Scaleway ACS URL - register in Authentik (SAML provider ACS). From bootstrap output."
  value       = var.sp_acs_url
}

# --- Bootstrap / admin ------------------------------------------------------
output "bootstrap_token" {
  description = "Initial akadmin bootstrap token (sensitive, one-shot flow - rotate after first login if you want)."
  value       = random_password.bootstrap_token.result
  sensitive   = true
}

output "bootstrap_email" {
  description = "Initial akadmin account email."
  value       = var.bootstrap_email
}
