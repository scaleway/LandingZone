# Architecture

> Landing-zone overview diagram.

<!-- TODO: architecture diagram (mermaid) - placeholder, to be filled -->

All stages read `scw-lz/envs/<env>/data/*-<env>.yaml` (plus tfvars overrides) and deploy through `for_each`. What gets created scales with the YAML you supply.

## Bootstrap

- **infra-ops project**: hosts the state bucket and the deploy identities
- **state bucket**: S3-compatible remote state for all stages (object-locked + SSE)
- **bootstrap SA + API key**: org CI/CD identity (deploy rights + IAM management)
- **lz-deploy SA + API key**: drives stages 1-6, one key per project
- **generated config files**: `backend-`/`providers-`/`remote_state-`/`5-backup-<env>.tfvars` consumed by stages 1-6
- **per-env creds files**: `.creds/lz-<env>-infra-ops.env` (bootstrap key) and `.creds/lz-<env>.env` (deploy key)
- **projects**: `dev` / `prod`
- **IAM**: lifecycle groups (`admins`, `developers`), service accounts, scoped policies
- **SSH key**: org `admin_key` (+ IAM registration + Secret Manager mirror)
- **KMS / audit bucket / secrets**: CMEK, centralized audit logs, generic secrets
- **SSO (SAML/SCIM)**: optional, disabled in the demo

## Stage 1: Security

- **Cockpit**: `metrics` / `logs` / `traces` data sources with write/read tokens
- **KMS key**: encryption
- **secret**: secret + version
- **security groups**: `bastion` / `web` / `internal` / `firewall` instance rules (mirrored to AZ1 for the fw-passive zone)

## Stage 2: Networking (hub-and-spoke)

- **VPCs**: `hub-net` (shared services), `spoke-1-net` (workload), `spoke-2-net` (workload)
- **Private networks**: one per VPC
- **VPC peerings**: spoke <=> hub, with the spoke-to-spoke routes
- **Public gateways / DNS / LBs / ACLs**: optional extras, not in the demo

## Stage 3: Security appliances (HA firewall)

- **HA firewall pair**: fw-passive/fw-active, OPNsense + CARP. 3 private NICs each (LAN/HA/WAN), HA-sync + egress VPCs, 2 CARP VIPs
- **egress public gateway**: NAT egress for spoke traffic (fixed public IP)
- **hub door public gateway + PAT**: the only management entry point (8443-8445/8022-8023 => firewall webui/SSH)
- **hub routes**: spoke 0/0 => hub => firewall CARP VIP
- **firewall mgmt SGs**: permissive management rules (incl. AZ1 copy)
- **image-import bucket**: golden firewall image import
- **golden image pipeline**: qcow2 => Block Snapshot => Block Volume, one chain per firewall node + zone
- **test instances**: `hub-test` / `spoke-1-test` / `spoke-2-test`

## Stage 4: Project factory

- **projects**: YAML-driven app/team projects (e.g. `team_a_app`, `team_b_data`)
- **VPC + private network per project**: each team's own network, peered to the hub
- **IAM groups**: per-team `admins` + `developers`
- **service accounts**: per-team RW/RO automation
- **IAM policies**: project-scoped permissions
- **object buckets**: team buckets (locked + SSE)

## Stage 5: Backup / DR

- **backup + DR buckets**: versioned primary (`fr-par`) + cross-region DR mirror (`nl-ams`), with lifecycle rules
- **KMS keys**: primary + DR region
- **backup SA + keys**: reads the state bucket, writes the backup buckets
- **sync jobs (cron)**: daily rclone state => primary backup => DR mirror
- **firewall exporter (cron)**: private container SSH-ing the firewall for configs + logs
- **restore drill (isolated state)**: scratch VPC, cold-restored fw pair + probe; all tagged `drill/restore/temporary`

## Stage 6: Interconnection

- **managed Site-to-Site VPN**: VGW-S on the hub (IPSec + BGP), customer gateway, routing policies, PSK in Secret Manager
- **emulated on-premises lab**: strongSwan + BIRD gateway on an elastic IP, cloud-CIDR routes, a test VM

> Details are code-first. Everything above comes from the actual `main.tf` / YAML in this repo. If the config differs, so does what gets deployed.

## The stages

| Stage | What it does |
|---|---|
| **1 - Security** | Centralized security posture: KMS, secret management, hardened access paths. |
| **2 - Networking** | Hub-and-spoke VPC design: private networks, public gateways, routing, DNS. |
| **3 - Security appliances** | HA firewall pair (CARP) at the heart of the hub, managed exclusively through a public-gateway door. OPNsense by default; Fortinet, Palo Alto, and pfSense are supported. Includes the golden-image pipeline and an automated firewall test battery. |
| **4 - Project factory** | YAML-driven creation of application and team projects, wired into the network and IAM. |
| **5 - Backup / DR** | Cross-region backup cascade: a daily two-tier copy (primary region + DR mirror) covering Terraform state, firewall configurations, and firewall logs, plus a restore drill. |
| **6 - Interconnection** | Hybrid edge: managed Site-to-Site VPN (VGW on the hub, IPSec/BGP), and an optional emulated on-premises site (strongSwan + BIRD customer gateway, lab VM) to validate the tunnel end-to-end. |

## Bootstrap

Before any stage, `make bootstrap` lays the foundation **per environment**: the `infra-ops` project, the Terraform state bucket, the deployment identity (bootstrap SA + lz deploy SA, one key per project), the org setup (the `<project_prefix>-<env>` project, default `lz-<env>`; IAM groups/SAs/SSH/KMS/audit/secrets), and the per-environment config files under `scw-lz/envs/<env>/` (backend, providers, remote state, 5-backup).

It runs with the owner key from `.creds/lz-creds.env` (see prerequisites). It generates the per-env credential files as it goes. The backup/DR buckets live in stage 5 (the `<project_prefix>-<env>` project). The firewall golden image pipeline lives in stage 3. Bootstrap owns no env-project data buckets.

See [orchestration.md](orchestration.md) for the bootstrap key chain and the stage ordering.
