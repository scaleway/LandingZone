# Backup / DR - RTO-RPO matrix (lz-dev)

Status: Phase A + B lanes live; restore drills executed (PASS).

## Rhythm

One scheduled backup per day, all UTC (cron in stage-5 variables.tf):

| Lane | Schedule (UTC) | Description |
|------|----------------|-------------|
| state_sync | 02:00 (`0 2 * * *`) | state bucket -> `lz-dev-backup/terraform-state` |
| dr_sync    | 02:05 (`5 2 * * *`) | primary -> `lz-dev-backup-dr` (nl-ams, full mirror) |
| fw export  | 02:30 (`30 2 * * *`) | FW config + logs -> primary, same night picked up by dr_sync |

Scheduled RPO baseline = 24h. The FW config lane has an *effective* RPO of
"since the last approved config apply" (config only changes on applies), so in
practice it is fresher than 24h.

## Matrix

| # | Asset | Live source | Backup chain | RPO | RTO | Restore mechanism | Retention (primary / DR) | Drilled? |
|---|-------|-------------|--------------|-----|-----|-------------------|---------------------------|----------|
| 1 | Terraform state | state bucket `lz-dev-terraform-state` (S3, **versioned**) | state_sync -> primary `terraform-state/` -> dr_sync -> DR | 24h | minutes | `aws s3 cp` DR -> state bucket, `terraform init -reconfigure` each stage | versioned (noncurrent 90d) / DR archive forever | No |
| 2 | FW config (fw_passive/fw_active.xml) | `/conf/config.xml` on each FW; source of truth = stage-3 rendered template | fw exporter 02:30 -> primary `firewall/config/<ts>/` -> dr_sync -> DR | 24h (effective: since last apply) | **measured ~4 min** (drill) | stage-3 provisioning path: golden boot volume + user_data XML + 99-metadata import hook, using the DR-sourced XML | primary prune 90d / DR archive forever | **Yes - PASS (drilled)** |
| 3 | FW operational logs (configd/system/filter/audit/hostwatch) | `/var/log/<svc>/latest.log` on each FW | fw exporter 02:30 (gzip) -> primary `firewall/logs/<ts>/` -> dr_sync -> DR | 24h | n/a (forensics/audit, not service restore) | `aws s3 cp` + gunzip | primary prune 30d / DR archive forever | Presence verified; formal restore not drilled |
| 4 | Secrets (Secret Manager) | SM (authoritative, versioned): backup SA keypair, fw-backup SSH key, admin SSH key | out of bucket-cascade scope; SM is the source of truth | n/a (immediate) | n/a | SM version rollback / rotation | SM versioning; no cross-region replication (managed service, static values) | n/a |
| 5 | Workloads / DB (Kapsule, DBaaS) | - | - | Phase C+ (pending), not started | - | - | - | No |

## Notes

- Live state bucket is S3-versioned, so accidental overwrites/deletions are
  recoverable in place; the two backup lanes cover bucket-level loss and add
  cross-region reach (DR).
- DR = long-term archive (copy-only, no --delete on either leg). Objects pruned
  from the primary (config >90d, logs >30d) remain in DR forever.
- Secrets are deliberately NOT stored in the buckets; SM holds the only copy.
  Cross-region secret replication was assessed and NOT adopted: SM is a
  managed service (region-resilient within the region)
  and our values are static non-dynamic inputs - recovery is a re-apply of
  Terraform inputs or re-rotation of an API key, not a data-loss risk. Keep
  the local key material (keys-<env>/, envs/<env>/backend-<env>.tfvars) as the
  off-cloud recovery copy.
- Image golden (`opnsense-central-fw.qcow2`) doubles as the restore boot
  source; `images/**` is excluded from backups by design (re-importable).

## Restore drill - EXECUTED (PASS)

Goal: prove a cold FW restore from the DR copy, and measure RTO for the matrix.

Stage 1 - artifact fidelity (no infra): latest `firewall/config/<latest-ts>/`
fw_passive/fw_active.xml fetched from the **DR** (nl-ams) bucket. xmllint well-formed; SHA256
identical to the primary copy; normalized diff vs the current rendered stage-3
template shows only OPNsense runtime metadata (ssl-certref, ipaddrv6, user/cert
records, empty containers, time stamp) - NO structural or security drift.
=> "the DR artifact is a valid, current, importable config".

Stage 2 - cold restore (temporary infra, destroyed after): scratch harness
under `drill/fw-restore/` (isolated VPC + 3 PNs + IPAM, same 10.x address plan).
Boot volumes cloned from the production golden SBS snapshots
(`opnsense-26.1-snap1`, distinct names). The DR-sourced XML was injected via
`user_data["opnsense_config"]` - the identical first-boot import path used in
production. A cloud-side probe container on the drill LAN PN verified the pair;
no local SSH was used.

Result (HTTP 200):
- fw-passive (fr-par-1): carp BACKUP vhid 10 advskew 100 + BACKUP vhid 11
- fw-active (fr-par-2): carp MASTER vhid 10 advskew 0 + MASTER vhid 11
- configd running (2 procs), hostnames fw-passive-fr-par-1 / fw-active-fr-par-2,
  LAN IPs 10.10.0.11/.12 from the DR copy.

Measured RTO:
- `terraform apply` (instances + volumes + NICs + config + serialized warm
  reboots): 121s
- Post-apply: cold stop/start per node (the in-module warm reboot wedges
  configd after a first-boot import - known production behaviour, learning
  #14; cold restart is the documented step) + CARP settle: ~2-3 min
- TOTAL restore-to-ready: ~4 min (excl. anything the state/namespace already
  provides; a fresh region would also need the IPAM/VPC scaffold from stage
  plumbing).

Teardown: `terraform destroy` removed all 27 drill resources in the same
session (verified: no drill instances/volumes remain; production FW pair +
golden snapshot + container namespace untouched).

Guardrails honoured: additive-only, temporary + destroyed, cloud-side only, no
local FW access, live FW pair untouched.

How to rerun:
  cd scw-lz/stages/5-backup/drill/fw-restore
  # fetch the latest export from the DR bucket into restore/fw{1,2}.xml
  terraform init -backend-config=../../../../envs/dev/backend-dev.tfvars
  terraform apply -var-file=../../../../envs/dev/providers-dev.tfvars \
    -var-file=../../../../envs/dev/remote_state-dev.tfvars \
    -var-file=../../../../envs/dev/5-backup-dev.tfvars
  # (networks are co-created: first apply needs -target=module.drill_vpc, or
  # apply twice - the count arg resolves once the PNs exist)
  curl -X POST -H "X-Auth-Token: <backup SA secret key>" \
    $(terraform output -raw probe_endpoint)/
  terraform destroy -var-file=../../../../envs/dev/providers-dev.tfvars \
    -var-file=../../../../envs/dev/remote_state-dev.tfvars \
    -var-file=../../../../envs/dev/5-backup-dev.tfvars
