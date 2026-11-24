# fw-restore drill harness

Cold-restore drill for the HA OPNsense pair (Stage 2 of the restore drill
plan - see `../../RTO-RPO.md`). Proves the DR-sourced firewall config restores
onto a fresh pair through the SAME provisioning path used in production, and
measures RTO. Executed successfully (fw-active MASTER / fw-passive BACKUP,
~4 min restore-to-ready); see `../../RTO-RPO.md` for results and
`../../README.md`.

## What it creates (all destroyed after)

- Scratch VPC + 3 Private Networks (lan 10.10.0.0/24, wan 10.4.0.0/24,
  ha 10.255.0.0/24) with IPAM - same address plan as production so the
  restored config's addresses match, but fully isolated.
- Two drill boot volumes cloned from the PRODUCTION golden SBS snapshots
  (`opnsense-26.1-snap1`) with distinct names - production snapshots/volumes
  are never referenced by key (only cloned as data).
- The restored pair: `modules/firewall` with `user_data["opnsense_config"]`
  = the DR-restored configs - the identical first-boot import path as stage 3.
- A cloud-side probe container (namespace reused from the exporter) on the
  drill LAN PN that SSH-probes the pair with the firewall backup key and
  reports hostname / configd / CARP state over HTTP. No local SSH.

## Security

- `restore/fw_passive.xml` + `restore/fw_active.xml` (the DR-sourced configs -
  contain the CARP password and SSH public keys) are gitignored; fetch them
  from the DR bucket, never commit them.
- The probe key arrives as a secret environment variable (same pattern as the
  exporter); the probe container is private (invoke with X-Auth-Token of the
  backup SA).

## Rerun

```bash
# 1. fetch the latest export from the DR bucket (backup SA creds, never echo):
#    s3://lz-dev-backup-dr/firewall/config/<latest-ts>/fw{1,2}.xml -> restore/
cd scw-lz/stages/5-backup/drill/fw-restore
terraform init -backend-config=../../../../envs/dev/backend-dev.tfvars

# 2. networks + volumes first (the firewall module's wan/ha counts can only
#    resolve once the PNs exist - same as production's stage split):
terraform apply -auto-approve -target=module.drill_vpc \
  -var-file=../../../../envs/dev/providers-dev.tfvars \
  -var-file=../../../../envs/dev/remote_state-dev.tfvars -var-file=../../../../envs/dev/5-backup-dev.tfvars

# 3. full cold-restore apply (time it for RTO); includes serialized reboots:
time terraform apply -auto-approve \
  -var-file=../../../../envs/dev/providers-dev.tfvars \
  -var-file=../../../../envs/dev/remote_state-dev.tfvars -var-file=../../../../envs/dev/5-backup-dev.tfvars

# 4. cloud-side verify:
curl -X POST -H "X-Auth-Token: <backup SA secret key>" \
  "$(terraform output -raw probe_endpoint)/"

# 5. NOTE: after apply, cold stop/start each node (the warm reboot included in
#    the module wedges configd after a first-boot import - production learning
#    #14), then re-run step 4 for the CARP-ready confirmation.

# 6. teardown (verifies nothing drill-scoped remains):
terraform destroy -auto-approve \
  -var-file=../../../../envs/dev/providers-dev.tfvars \
  -var-file=../../../../envs/dev/remote_state-dev.tfvars -var-file=../../../../envs/dev/5-backup-dev.tfvars
```
