# Scaleway IAM SSO Module (SAML + SCIM)

Org-level identity federation as code: enables SAML on the Scaleway
organization, points the Service Provider at your IdP (Authentik, Entra ID,
Okta, ...), attaches IdP signing certificates, and optionally enables SCIM for
automated user/group provisioning.

> Requires **Terraform >= 1.14** (provider Actions feature) and provider
> **>= 2.83**.

## Usage

```hcl
module "sso" {
  source = "./modules/iam-sso"

  organization_id = "11111111-1111-1111-1111-111111111111"
  enabled         = true

  entity_id          = "https://idp.example.com/saml/metadata"
  single_sign_on_url = "https://idp.example.com/saml/sso"
  enable_scim        = true

  idp_signing_certificates = [
    {
      type    = "signing"
      content = file("idp-signing.crt")
    },
  ]
}
```

Disabled by default: `enabled = false` creates nothing and produces no drift -
safe for organizations that do not (yet) use SSO or federate through another
IdP.

## How the SAML handshake works

1. `scaleway_iam_saml` enables the organization's SAML Service Provider and
   exposes its metadata (`sp_entity_id`, `acs_url` outputs) - register those on
   the IdP side.
2. The provider **Action** `scaleway_iam_update_saml_configuration` (a
   Terraform 1.14+ feature) points the SP at the IdP: `entity_id` +
   `single_sign_on_url`. The action fires `after_create` of the SAML resource.
3. `scaleway_iam_saml_certificate` attaches the IdP signing certificate(s) used
   to validate Assertions (`type` is a provider-defined string, e.g. `signing`).
4. `scaleway_iam_scim` + `scaleway_iam_scim_token` (opt-in) give the IdP a
   SCIM endpoint to provision users/groups. SCIM is an **Early Access** feature
   - it may need to be enabled for your organization by Scaleway.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| organization_id | Scaleway Organization ID. | `string` | n/a | yes |
| enabled | Master switch. false = no-op. | `bool` | `false` | no |
| entity_id | Entity ID of the SAML IdP. | `string` | `null` | no |
| single_sign_on_url | Single Sign-On URL of the SAML IdP. | `string` | `null` | no |
| idp_signing_certificates | IdP signing certificates `[{ type, content }]`. | `list(object)` | `[]` | no |
| enable_scim | Enable SCIM user/group provisioning. | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| saml_id | ID of the organization SAML configuration. |
| saml_status | Status of the SAML configuration. |
| sp_entity_id | SP entity ID (register on the IdP side). |
| acs_url | Assertion Consumer Service URL (register on the IdP side). |
| idp_entity_id | Configured IdP entity ID. |
| idp_single_sign_on_url | Configured IdP SSO URL. |
| saml_certificate_ids | IDs of attached IdP signing certificates. |
| scim_id | ID of the SCIM configuration. |
| scim_bearer_token | SCIM bearer token (**sensitive**). |

## Gotchas / operational notes

- **Lockout risk.** Once SAML is enabled, organization *members* can only
  authenticate with the methods an admin has enabled; the **Owner is exempt**
  and always logs in via password/OAuth2. Roll out gradually: enable SAML,
  validate a test member through the IdP, and only then disable other auth
  methods. The break-glass is the Owner account.
- **SCIM token rotation.** `scaleway_iam_scim_token` cannot be updated
  ("create a new one to rotate"). Mirror the value to Secret Manager from the
  caller via `data_wo` (never in state), like the SSH-key mirror in bootstrap.
- **SCIM requires SCIM enabled per-org** (Early Access). If the API rejects it,
  contact Scaleway to enable SCIM for the organization before setting
  `enable_scim = true`.
- **SAML config is a one-shot Action.** The `entity_id`/`single_sign_on_url`
  are applied after the SAML resource is created. To change the IdP, replace
  the SAML resource (which replays the action) - plan carefully, it briefly
  re-configures the org SP.
