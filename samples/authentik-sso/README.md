# Sample: Authentik IdP for console SSO (SAML + SCIM)

Part B of the SSO extension. A standalone, self-contained sample that deploys
**Authentik** (self-hosted identity provider) on a Scaleway instance and wires
it into the org-level SAML/SCIM federation that **bootstrap** manages (Part A,
`modules/iam-sso`).

```
   Scaleway console (SP, bootstrap)               Authentik (IdP, this sample)
   ------------------------------               ------------------------------
   scaleway_iam_saml                <--------   sp_entity_id + acs_url
   entity_id / single_sign_on_url   <--------   idp_entity_id + idp_sso_url
   scaleway_iam_saml_certificate    <--------   idp signing certificate (PEM)
   scaleway_iam_scim(_token)        <--------   SCIM provisioning endpoint
```

The sample uses the toolkit modules (`instance-vm`, `security-group`) and
nothing else: one Ubuntu instance, Docker + the official Authentik
docker-compose (server + worker + embedded PostgreSQL 16 / Redis 7), HTTPS on
443 (Authentik's built-in self-signed TLS - bring a real cert or a load
balancer for production).

## What you get

| Output | Meaning |
|--------|---------|
| `public_ip` / `url` / `url_by_ip` | Where to reach the IdP |
| `idp_entity_id` / `idp_sso_url` | **Feed back** into bootstrap `sso.<key>` (in `envs/<env>/data/org-<env>.yaml`; `entity_id`, `single_sign_on_url`) |
| `scw_sp_entity_id` / `scw_acs_url` | SCW SP metadata (from bootstrap) - register inside Authentik |
| `bootstrap_token` / `bootstrap_email` | Initial akadmin login (sensitive) |
| `scripts/configure_scw_saml.py` | Optional API helper to register the SCW provider + app + print the signing cert |

## Prerequisites

- A running **bootstrap** stage with `sso:` enabled (Part A) - pick up its
  outputs (bootstrap uses LOCAL state):
  ```bash
  cd scw-lz/bootstrap
  terraform output -state=../envs/<env>/bootstrap-<env>.tfstate -json sso  # -> sp_entity_id, acs_url
  ```
- Terraform >= 1.5, a Scaleway org key, and a project to deploy into.
- Ports 80/443 reachable from end-user browsers (SAML redirects go through the
  USER's browser, not server-to-server).

## Deploy

```bash
cd samples/authentik-sso
cp terraform.tfvars.sample terraform.tfvars   # fill org/project/FQDN, restrict CIDRs
terraform init
terraform plan            # dry-run before apply
terraform apply
terraform output          # note public_ip, bootstrap_token, idp_entity_id
```

Point DNS (`auth.example.com` -> `public_ip`) or test directly on
`url_by_ip` (self-signed TLS - accept the browser warning; or use
`curl -k https://<ip>/if/flow/initial/` to check the WebUI responds).
First boot pulls images + provisions the DB - give it a few minutes.

## Register the Scaleway SP inside Authentik

Two ways (either one ends with the IdP-side application existing):

**A. UI (the official Scaleway "Set up SSO with Authentik" flow)**
1. Log in as `akadmin` (bootstrap token) at `https://<idp>/`
2. Applications -> Providers -> Create -> **SAML Provider**
   - Name: `Scaleway`, ACS URL: `scw_acs_url`, Issuer: `scw_entity_id`
   - Signing Certificate: Authentik self-signed; toggle Sign assertions/responses
   - **NameID Mapping: Authentik default "Username"** (SCW maps users on username)
3. Applications -> Create -> Application: name `Scaleway`, provider = the one above
4. Download the provider's **signing certificate** (PEM)

**B. API helper (optional)**
```bash
python3 samples/authentik-sso/scripts/configure_scw_saml.py \
  --base-url https://<idp> \
  --bootstrap-token "$(terraform output -raw bootstrap_token)" \
  --sp-entity-id <scw_sp_entity_id> \
  --sp-acs-url  <scw_acs_url> \
  --insecure                    # if testing on self-signed 443
```
Best-effort helper; adapt to your Authentik version if the API drifts.

## Complete the handshake (bootstrap)

Authentik's IdP values + the signing cert go back into the org factory, then
re-apply bootstrap (which is where the SAML action + certificate live):

```yaml
# scw-lz/envs/<env>/data/org-<env>.yaml
sso:
  authentik:
    enabled: true
    entity_id: https://auth.example.com/application/o/scaleway/
    single_sign_on_url: https://auth.example.com/application/o/scaleway/
    enable_scim: true                        # optional, Early Access
    store_scim_token_in_secret_manager: true
    project_key: dev
    certs:
      - type: signing
        content: |
          -----BEGIN CERTIFICATE-----
          <Authentik signing cert PEM>
          -----END CERTIFICATE-----
```

```bash
cd scw-lz/bootstrap
terraform init
terraform plan -state=../envs/<env>/bootstrap-<env>.tfstate    # review: adds SAML config + cert (+ SCIM if enabled)
terraform apply -state=../envs/<env>/bootstrap-<env>.tfstate
```

## Verify

1. On Scaleway console, log in **as a member** (not Owner) -> use `Log in with SSO`
   - you should land on Authentik, authenticate, and return to the console
   - SCIM (if enabled): the IdP can provision/deprovision members automatically
2. Failover: with SAML enabled, members can ONLY log in via the IdP. The
   **Owner account is the break-glass** (exempt from SAML).
3. Gradual rollout rule: validate one test member first, then disable the other
   auth methods in a separate, deliberate step (not in the same apply).

## Gotchas / ops notes

- **Secrets in state.** The generated compose (incl. bootstrap token, DB
  password) is embedded in the instance's user-data -> visible in Terraform
  state. Fine for a sandbox/reference; for production rotate the bootstrap
  token after first login and move secrets to Secret Manager.
- **Single-node.** Embedded Postgres/Redis + a single server = acceptable for a
  small team/reference only. Production evolution: managed RDB + managed Redis,
  instance behind a Load Balancer, and a second node for HA.
- **TLS.** Authentik's built-in HTTPS is self-signed. Put a real cert on it (or
  terminate at an LB) before onboarding real users.
- **DNS / public IP.** SAML depends on a stable, reachable IdP URL. Point a DNS
  record at the flexible IP; note the Scaleway routed-IP caveat (verify inbound
  reachability from your network).
- **SCIM is Early Access / org-gated** on the Scaleway side - the API rejects it
  until Scaleway enables SCIM for your org.
