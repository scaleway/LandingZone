# Development

## Quality gate and tests

- **`./scripts/validate.sh`**: the full repo gate. Runs formatting, validate, tflint, tfsec, and repo hygiene. Cheap enough to run on every change.
- **`make test`**: the offline regression suite under `tests/`. Covers the firewall failover logic (mocked API), the firewall backup tool (mocked SSH), and the CLI driver (`tests/test_driver.sh`, runs against a fake terraform). No cloud access, no credentials.
- Terraform provider versions are pinned with committed `.terraform.lock.hcl` files; the Terraform binary version with `.terraform-version`.

## Design principles

- **Contracts between stages**: every stage declares its inputs and outputs and can run independently.
- **Security first**: least privilege through groups, service accounts, and scoped IAM policies.
- **Resource factories**: YAML-driven configuration for projects, networks, and firewall rules.
- **Explicit over magic**: flat, low-complexity Terraform; minimal indirection.
- **No side effects**: pure Terraform; any operational script stays in `scripts/` as a thin, shared driver.
- **Common tags on every resource**: every resource carries `managed-by=landing-zone-toolkit`, `env=<environment>` and `stage=<stage>`. List resources get them via `concat(local.common_tags, ...)`; object buckets via `merge(local.common_tags_map, ...)`. Stage-specific roles are appended as extra tags (e.g. `fw_passive`, `egress`, `pgw-hub`). The separator is `=` (not `:`): Scaleway's IAM tag schema rejects `:` in tag values, so the markers are formatted `key=value`. `scripts/validate.sh` enforces this; never drop the common set from a resource.
