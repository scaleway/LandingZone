# Stage 5 - Backup / DR

Cross-region disaster-recovery for the landing zone. One scheduled backup per
day; a two-tier cascade keeps a coherent copy in fr-par and a full mirror in
nl-ams (DR) that doubles as the long-term archive.

## How it works (design)

### Two-tier backup cascade

```
state bucket --state_sync (02:00 UTC)--> lz-<env>-backup/terraform-state (primary)
                                             |
                       FW exports/logs land here (cloud-side exporter)
                                             |
                                             v dr_sync (02:05 UTC, full mirror at root)
                                   lz-<env>-backup-dr (nl-ams, replica + archive)
```

- **state_sync** (serverless job, daily 02:00 UTC): state bucket ->
  primary `terraform-state/` (excludes `images/**`). Runs in seconds.
- **dr_sync** (serverless job, daily 02:05 UTC): full copy of the primary ->
  DR at the bucket root. New backup sources (FW exports, future DB/Kapsule)
  need zero DR plumbing.
- Both legs are **copy-only** (rclone `--check-first --checksum`, no
  `--delete`): objects pruned on the primary stay in DR -> DR is the archive.
- **FW export** (serverless container on the hub LAN PN, daily 02:30 UTC):
  pulls `/conf/config.xml` + the bounded per-service logs from each firewall
  with the dedicated backup SSH key, then uploads to
  `firewall/config/<ts>/fw<N>.xml` and `firewall/logs/<ts>/fw<N>-<name>.log.gz`.
  Runs after dr_sync so the same night's mirror picks everything up.

### Rhythm

One backup per day (RPO baseline 24h): state_sync 02:00, dr_sync 02:05,
fw export 02:30 UTC. The FW config lane is effectively fresher (config only
changes on approved applies).

### Retention (decided)

- Primary bucket: current-version age deletion is done by the roles' prune
  steps (S3 lifecycle can't do it - provider bug, see Gotchas): FW configs
  >90d, FW logs >30d; lifecycle covers noncurrent-version cleanup (90d) +
  abort-incomplete multiparts (7d).
- DR bucket: **keeps everything** - the long-term archive. Growth is ~MB/day;
  noncurrent churn is still bounded by the 90d lifecycle.
- All buckets AES256 (Scaleway SSE-KMS is broken). KMS keys reserved.

### Secrets

All credentials live in **Secret Manager** (write-only `data_wo`, never in
state): backup SA API keypair, the firewall backup SSH private key. The FW
backup public key is also composed into the stage-3 `authorizedkeys` (gated
refresh) so the cloud-side exporter can log in.

## RTO / RPO and restore drills

See `RTO-RPO.md` for the full matrix. Summary:

| Asset | RPO | RTO | Drilled |
|-------|-----|-----|---------|
| Terraform state | 24h | minutes | No |
| FW config (HA pair) | 24h (since last apply) | ~4 min | **Yes - PASS (drilled)** |
| FW logs | 24h | n/a (forensics) | Presence verified |
| Secrets (SM) | n/a | n/a | out of bucket scope |

Restore drill result: the DR-sourced configs were imported onto a
scratch pair booted from the same golden snapshots via the same first-boot
path; verified cloud-side -> fw-active MASTER / fw-passive BACKUP (both CARP
vhids), configd healthy. Total restore-to-ready ~4 min. All scratch resources
were destroyed. Rerun instructions are in `RTO-RPO.md` and the
`drill/fw-restore/`
README.

## Access

- Buckets (read/verify): backup SA creds, read from Secret Manager with
  `scw secret version access <id> revision=1 raw=true` (never echoed).
- Endpoints: primary `https://s3.fr-par.scw.cloud`, DR
  `https://s3.nl-ams.scw.cloud`.
- Private container invoke (exporter/probe):
  `curl -X POST -H "X-Auth-Token: <backup SA secret key>" <endpoint>/`
  (backup SA holds ContainersPrivateAccess).
- Manual job run: `scw jobs definition start <job-id> region=fr-par` (run id
  in `JobRuns.0.ID`), wait via `scw jobs run wait <run-id>`.
- Drives are never touched from a workspace: exports and verification are
  cloud-side.

## Recipe - run and validate

```bash
cd scw-lz/stages/5-backup
terraform init -backend-config=../../envs/dev/backend-dev.tfvars
terraform plan -input=false \
  -var-file=../../envs/dev/providers-dev.tfvars \
  -var-file=../../envs/dev/remote_state-dev.tfvars \
  -var-file=../../envs/dev/5-backup-dev.tfvars    # bootstrap-generated per env
terraform apply <same flags>          # only after explicit review/go

# verify a fresh daily run:
scw jobs run list                       # 02:00 / 02:05 runs
aws s3 ls s3://lz-dev-backup/firewall/            (primary)
aws s3 ls s3://lz-dev-backup-dr/firewall/         (DR, nl-ams)

cd ../../.. && ./scripts/validate.sh
```

## Operational notes

- **Object storage encryption**: use AES256 (SSE-S3) for buckets; KMS-based
  server-side encryption is not available for Object Storage buckets.
- **Object retention**: age-based lifecycle rules are not used; retention is
  handled by the prune steps in the jobs.
- **OPNsense 26.x log layout**: logs are per-service directories with a
  `latest.log` pointer; the flat `/var/log/*.log` files no longer exist.
  Export `latest.log`, gzipped.
- **Container env**: `PORT` is reserved; `secret_environment_variables` is a
  value map, not a secret-id reference.
- **Scale-to-zero**: computes per-run identities (timestamps) per request, not
  per process. One node may be briefly unreachable right after a reboot while
  CARP settles; the exporter retries.
- **Firewall restart after config import**: a cold stop/start is the reliable
  convergence step for the HA pair.

## Future evolution

- Phase B next: admin key rotation at next FW maintenance; credential rotation
  before the repo goes public.
- No cross-region Secret Manager replication - SM is a managed service and our
  secret values are static (no dynamic data); recovery is a Terraform re-apply
  of inputs or key rotation. Local key material (keys-<env>/,
  envs/<env>/backend-<env>.tfvars) remains the off-cloud copy. Not implemented.
- Phase C (not started): DB / Kapsule backups into the same cascade (dr_sync
  mirrors them with zero plumbing changes).
