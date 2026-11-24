variable "organization_id" {
  description = "Scaleway Organization ID the SAML/SCIM configuration applies to (org-level identity, not project-scoped)."
  type        = string
}

variable "enabled" {
  description = "Master switch. false (default) = the module manages nothing (safe no-op for orgs not using SSO)."
  type        = bool
  default     = false
}

variable "entity_id" {
  description = "Entity ID (issuer) of the SAML Identity Provider (Authentik, Entra ID, Okta...). Applied on the Scaleway side via the iam_update_saml_configuration action after SAML is enabled."
  type        = string
  default     = null
}

variable "single_sign_on_url" {
  description = "Single Sign-On URL of the SAML Identity Provider."
  type        = string
  default     = null
}

variable "idp_signing_certificates" {
  description = "IdP signing certificates to attach to the SAML configuration (type is a provider-defined string, e.g. \"signing\")."
  type = list(object({
    type    = string
    content = string
  }))
  default = []
}

variable "enable_scim" {
  description = "Enable SCIM for automated user/group provisioning. SCIM is an Early Access feature and may need to be enabled for the organization by Scaleway - the API errors clearly if not."
  type        = bool
  default     = false
}
