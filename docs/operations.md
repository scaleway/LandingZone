# Operations

Day-to-day command and configuration reference.

## CLI

| Command | What it does |
|---|---|
| `./scripts/apply.sh [ENV] [--skip-bootstrap] [--plan] [--stage <key>]` | Apply (or dry-run) stages in order. |
| `./scripts/destroy.sh [ENV] [--skip-bootstrap] [--stage <key>]` | Destroy stages in reverse order. |

A positional environment wins over `$ENV`, which wins over the `dev` default. Flags can appear anywhere on the command line.

Common flags (full semantics in [orchestration.md](orchestration.md)):

| Flag | What it does |
|---|---|
| `--stage <key>` | One stage only: accepts the key (`3-security-appliances`), the number (`3`), or the alias (`stage-3`). Also accepts `bootstrap`. |
| `--plan` | Dry-run: `terraform plan` for every stage, changes nothing. |
| `--skip-bootstrap` | Skip the bootstrap stage (already run). |
| `--everything` (destroy) | Also destroy the foundation: stage-1 + bootstrap. |

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `ORG_ID` | n/a (required; from `.creds/lz-creds.env` or exported) | Scaleway organization ID. |
| `ENV` | `dev` | Environment name (`dev`, `prod`, ...). |
| `REGION` | `fr-par` | Primary region. |
| `ZONE` | `fr-par-2` | Primary availability zone. |

## Teardown commands

```bash
make destroy STAGE=3            # tear down ONLY stage 3
make destroy                    # all workload stages 2-6, reverse order (buckets
                                # are emptied automatically; stage-1 + bootstrap kept)
make destroy-keep-bootstrap     # workload stages + stage-1, keep bootstrap
make destroy STAGE=bootstrap    # foundation only: state bucket, projects, IAM
```

Destroy in order: workloads first, foundation last. `make destroy` keeps the stage-1 security baseline and the bootstrap foundation. `make destroy STAGE=bootstrap` removes the foundation and auto-loads the org-level owner key (`.creds/lz-creds.env`) - bootstrap's own SA keys cannot destroy it (self-brick guard, see [orchestration.md](orchestration.md)). Always `make plan`-gate first. Use `STAGE=<n>` to tear down a single stage.
