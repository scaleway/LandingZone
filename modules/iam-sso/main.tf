# ---------------------------------------------------------------------------
# SSO - org-level identity federation (SAML + SCIM) as code.
#
# Requires Terraform >= 1.14 (provider Actions feature) and provider >= 2.83.
# Disabled by default: enabled=false creates nothing and produces no drift.
#
# Two-way handshake (see README + Scaleway "Set up identity federation"):
#   1. scaleway_iam_saml enables the org SP and exposes its metadata
#      (outputs sp_entity_id / acs_url) for the IdP (Authentik/Entra/Okta).
#   2. The IAM update action points the SP at the IdP (entity_id + SSO URL).
#   3. IdP signing certificates validate the Assertions.
#   4. SCIM (opt-in) lets the IdP provision users/groups automatically.
# ---------------------------------------------------------------------------

locals {
  # One-element maps when enabled: for_each = {} in the disabled state is a
  # safe no-op (per-instance bodies, including the action_trigger reference,
  # are not evaluated for zero instances).
  sso  = var.enabled ? { main = true } : {}
  scim = var.enabled && var.enable_scim ? { main = true } : {}
}

# --- 1. SAML: enable the Service Provider on the organization -------------
resource "scaleway_iam_saml" "main" {
  for_each = local.sso

  organization_id = var.organization_id

  # Once the SP exists, immediately point it at the IdP (entity ID + SSO URL)
  # via the provider Action. after_create only: config changes are applied
  # through a replace of this resource if entity_id/single_sign_on_url change.
  lifecycle {
    action_trigger {
      events  = [after_create]
      actions = [action.scaleway_iam_update_saml_configuration.main[each.key]]
    }
  }
}

# --- 2. Point the SP at the IdP -------------------------------------------
action "scaleway_iam_update_saml_configuration" "main" {
  for_each = local.sso

  config {
    organization_id    = scaleway_iam_saml.main[each.key].organization_id
    entity_id          = var.entity_id
    single_sign_on_url = var.single_sign_on_url
  }
}

# --- 3a. IdP signing certificates ------------------------------------------
resource "scaleway_iam_saml_certificate" "main" {
  for_each = var.enabled ? { for i, c in var.idp_signing_certificates : format("cert-%02d", i) => c } : {}

  saml_id         = scaleway_iam_saml.main["main"].id
  organization_id = var.organization_id
  type            = each.value.type
  content         = each.value.content
}

# --- 4. SCIM: automated provisioning of users/groups -----------------------
resource "scaleway_iam_scim" "main" {
  for_each = local.scim

  organization_id = var.organization_id
}

# SCIM bearer token - expires and is NOT sensibly updatable (see provider
# schema: "to rotate the token, create a new one"). Mirror it to Secret
# Manager from the caller (data_wo) if it should survive a state refresh.
resource "scaleway_iam_scim_token" "main" {
  for_each = local.scim

  scim_id         = scaleway_iam_scim.main[each.key].id
  organization_id = var.organization_id
}
