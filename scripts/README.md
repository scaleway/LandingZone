# Scripts

Repo command-line entry points and helper tools. `apply.sh` and `destroy.sh`
are the main driving scripts; everything else is a focused utility. See
`docs/orchestration.md` for stage ordering and `docs/operations.md` for
day-to-day usage.

## Orchestration

| Script | Purpose |
|---|---|
| `apply.sh` | Apply stages in order. Flags: `--skip-bootstrap`, `--plan` (dry-run), `--stage <key>`, `--replace <addr>` (manual forced reinstall, not needed for image rotation). |
| `destroy.sh` | Destroy stages in reverse order. `--everything` also destroys the foundation (stage 1 + bootstrap). |
| `lib/stages.sh` | Shared stage driver: CLI parsing, stage registry, ordering, terraform invocation. `apply.sh` and `destroy.sh` are thin front-ends over it. |
| `validate.sh` | Repo-wide quality gate before commit: `terraform fmt -check`, plan checks, shell syntax. `./scripts/validate.sh [ENV]` |

## Firewall image and user-data

| Script | Purpose |
|---|---|
| `fw-extra-render.py` | Render `#cloud-config` => shell script, the golden-image hook that runs on the node. Supports `write_files` + `runcmd` only. Used by the golden-image pipeline. |
| `fw-extra-apply.sh` | Apply `#cloud-config` => node config through the hub door PAT. No instance rebuild, no FW reboot. Hash-idempotent (see stage-3 `extra_user_data`, dual-channel cloud-init in `scw-lz/stages/3-security-appliances/README.md`). |
| `test_fw_extra_render.py` | Unit tests for `fw-extra-render.py`. `python3 scripts/test_fw_extra_render.py` |
| `build_fw_template.py` | Build a reusable, sanitized OPNsense config template from a live config export. `python3 scripts/build_fw_template.py <source-config.xml> [output-dir]` |

## Firewall test battery

| Script | Purpose |
|---|---|
| `gen_fw_battery_env.sh` | Generate `test-firewalls.env` (door IP, firewall UUIDs) consumed by the stage-3 battery. `./scripts/gen_fw_battery_env.sh [ENV]` |

The battery itself lives in
`scw-lz/stages/3-security-appliances/providers/opnsense/test-firewalls.sh`.

## Cleanup tools

Terraform destroy does not remove everything. These scripts purge leftovers
after a teardown.

| Script | Purpose |
|---|---|
| `delete_iam.sh` | Purge leftover env-scoped IAM. The destroy graph revokes the SA keys early, which leaves IAM policies that `terraform destroy` can no longer remove. |
| `delete_s3.sh` | Empty and delete an S3 bucket. `./scripts/delete_s3.sh <bucket>` |
| `delete_vpn_secrets.sh` | Purge leftover S2S VPN PSK secrets in Secret Manager. |
