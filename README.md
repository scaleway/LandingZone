# Scaleway Landing Zone Toolkit

Build a **hub-and-spoke landing zone on Scaleway** with Terraform. One hub network holds security, egress and connectivity. Spokes hold workloads, isolated from each other.

Deploy in stages: a day-0 bootstrap, then six workload stages. It ships with 30+ reusable modules and ready-to-run examples.

Every stage has defined inputs and outputs. Deploy one stage, the whole chain, or your own combination.

## Architecture overview

![Scaleway LDZ Toolkit HLD](docs/Scaleway%20LDZ%20Toolkit%20HLD.drawio.png)

Editable source (open in [draw.io](https://app.diagrams.net/) / diagrams.net): [`docs/Scaleway-Toolkit.drawio.xml`](docs/Scaleway-Toolkit.drawio.xml) or [`docs/Scaleway-Toolkit.drawio`](docs/Scaleway-Toolkit.drawio), the `.xml` variant declares the XML header so it also renders in XML viewers. Contains the HLD + annexes (firewall deploy flow, Scaleway product icons); 
PNG export: `docs/Scaleway LDZ Toolkit HLD.drawio.png`.

## Hub-and-spoke by design

Everything centers on one component: the **hub network**.

- **One inspection point**: all traffic between spokes, and all traffic leaving the zone, crosses the HA firewall pair. Write policy once, enforce everywhere.
- **One egress path**: NAT egress through the firewall VIP and the egress public gateway. No per-spoke Internet access.
- **Central connectivity**: the Site-to-Site VPN terminates at the hub. Every spoke reaches the remote site over one tunnel. No per-spoke VPNs.
- **Isolated spokes**: workloads live in their own VPCs, reachable only through your policies. Add a spoke with one YAML entry.
- **Cheaper, simpler**: one security, egress and connectivity point, not one per network.

## What you get

- **Staged landing zone** (`scw-lz/`): bootstrap once, then org setup, security, networking, HA firewalls, project factory, cross-region backups, hybrid interconnection.
- **Reusable modules** (`modules/`): 30+ building blocks (VPC, IAM, compute, object storage, K8s, DNS, serverless, and more), kept close to the Scaleway provider. Predictable and forkable.
- **Working examples** (`samples/`): standalone end-to-end templates. Deploy as-is.
- **Clean command line**: `apply.sh` / `destroy.sh` share one driver. Stage filters, dry-runs, and environment switching, with no duplicated logic.
- **Quality gate and offline tests**: `validate.sh` and the `tests/` suite run with no cloud access and no credentials.

## Documentation

| Topic | Where |
|---|---|
| Architecture & stages | [`docs/architecture.md`](docs/architecture.md) |
| Components & repository layout | [`docs/components.md`](docs/components.md) |
| Orchestration (ordering, keys, teardown) | [`docs/orchestration.md`](docs/orchestration.md) |
| Operations (CLI, env, teardown) | [`docs/operations.md`](docs/operations.md) |
| Development (tests, principles) | [`docs/development.md`](docs/development.md) |
| Samples & extra design notes | [Samples and docs](#samples-and-docs) |
| Contributing guide | [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md) |

## Quick start

### 1. Prerequisites

- Terraform **1.16.5** (`>= 1.14` works; `tfenv` picks up the pinned `.terraform-version`)
- A Scaleway account with an **org admin API key** (the "owner" key). Bootstrap uses it to create everything else.
- The **Scaleway CLI** (`scw`, `brew install scaleway-cli`): IAM cleanup (`delete_iam.sh`, `delete_vpn_secrets.sh`) and stage-3 firewall reboot
- The **AWS CLI** (`aws`, `brew install awscli`): S3 API calls for Object Storage (`delete_s3.sh`)
- `make` and a POSIX shell (macOS or Linux)

### 2. Prepare the owner key (once, before the first bootstrap)

Create `.creds/lz-creds.env` **in the root of your local checkout**. The `.creds/` folder is gitignored. It never appears in your commits.

The toolkit never generates your owner key. You provide it once, in `.creds/lz-creds.env`. It is the **day-0 fallback** whenever per-env files don't exist yet. A fresh checkout boots with no manual exports:

```bash
mkdir -p .creds
cp templates/creds/lz-creds.env .creds/lz-creds.env
$EDITOR .creds/lz-creds.env              # fill in SCW_ACCESS_KEY / SCW_SECRET_KEY / ORG_ID
```

`make bootstrap` loads it, then writes the per-env keys it creates:
`.creds/lz-<env>.env` (lz deploy key, stages 1-6) and
`.creds/lz-<env>-infra-ops.env` (bootstrap key). Later runs need nothing more.
Or you can skip the file and export the keys in your shell instead. Exported keys always win.

```bash
export ENV=dev                           # optional, defaults to dev
```

### 3. Bootstrap once per environment

```bash
make bootstrap                 # creates the state bucket + env config
```

This generates everything under `scw-lz/envs/<env>/`. Run again with `ENV=prod` for a second environment.

### 4. Deploy

```bash
make apply                     # all stages, in order
# or one stage at a time (stage as a flag):
make apply STAGE=3             # just the HA firewall pair
make apply STAGE=3 ENV=prod    # against the prod env config

# always dry-run first:
make plan STAGE=3              # or: ./scripts/apply.sh --stage 3 --plan
```

### 5. Verify

```bash
./scripts/validate.sh         # repo quality gate (fmt, validate, lint, hygiene)
make test                     # offline regression suite (no cloud, no credentials)
```

### 6. Tear down (use with care)

```bash
make destroy STAGE=3            # tear down ONLY stage 3
make destroy                    # all workload stages 2-6, reverse order (buckets
                                # are emptied automatically; stage-1 + bootstrap kept)
make destroy-keep-bootstrap     # workload stages + stage-1, keep bootstrap
make destroy STAGE=bootstrap    # foundation only: state bucket, projects, IAM
```

Destroy order: workloads first, foundation last. `make destroy` keeps stage-1 and bootstrap. `make destroy STAGE=bootstrap` removes the foundation and auto-loads the org-level owner key (`.creds/lz-creds.env`). Bootstrap's own SA keys cannot destroy it. Always `make plan` first. Use `STAGE=<n>` to tear down a single stage.

See [`docs/orchestration.md`](docs/orchestration.md#teardown-order) for the full teardown order: IAM dies last, object-locked state bucket, self-brick guard.

## Samples and docs

- `samples/authentik-sso/`: the reference end-to-end example (SCIM/SSO federation with the IAM).
- Committed `data/<topic>-<env>.yaml` and `<stage>-<env>.tfvars` files are sanitized **templates**. Live per-env data lives gitignored under the `-demo` suffix. Every stage prefers the `-demo` file, then falls back to the template.
- `docs/Scaleway-Toolkit.drawio.xml` / `docs/Scaleway-Toolkit.drawio`: full landing-zone HLD (3 pages: topology, firewall deploy flow, Scaleway icons) — editable in draw.io; PNG export `docs/Scaleway LDZ Toolkit HLD.drawio.png`.
- `docs/carp-failover.mmd`: stage-3 CARP failover sequence (mermaid).
- `docs/opnsense-scaleway-cookbook.md`: step-by-step guide to running OPNsense on Scaleway.

## Reference

- [Scaleway Terraform provider documentation](https://registry.terraform.io/providers/scaleway/scaleway/latest/docs)

## License

Copyright 2026 Scaleway. Licensed under the [Apache License, Version 2.0](LICENSE) (the "License"); you may not use this repository except in compliance with the License. Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.

Contributions are welcome under the same license - see [`docs/CONTRIBUTING.md`](docs/CONTRIBUTING.md).
