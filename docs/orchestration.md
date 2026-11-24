# Orchestration

> How the stages are ordered and orchestrated, how the identity/key chain works, and what happens on teardown.

<!-- TODO: orchestration diagram (mermaid) - placeholder, to be filled -->

## Stage sequencing

One shared driver orders every run: `scripts/lib/stages.sh`. `apply.sh` and `destroy.sh` are thin front-ends over it.

- **Apply**: stages run **forward** (`bootstrap => 1 => 2 => 3 => 4 => 5 => 6`).
- **Destroy**: stages run **reverse** (`6 => 5 => 4 => 3 => 2 => 1 => bootstrap`). Workloads first, foundation last.
- **Stage-4 (project factory) is disabled by default**. It runs only when the per-env demo tfvars (`4-project-factory-<env>-demo.tfvars`) exists, or when selected explicitly with `--stage 4`.
- **Destroy keeps the foundation by default**: plain `make destroy` tears down only the workload stages (2-6). Stage-1 + bootstrap are kept unless you opt in.

| Flag | Effect |
|---|---|
| `--stage <key>` | Only one stage: accepts the key (`3-security-appliances`), the number (`3`), or the alias (`stage-3`). Also accepts `bootstrap`. |
| `--plan` | Dry-run (`terraform plan`) for every stage; changes nothing. Apply only. |
| `--skip-bootstrap` | Skip the bootstrap stage entirely (already run). |
| `--everything` (destroy) | Also destroy the foundation: stage-1 + bootstrap. `make destroy-keep-bootstrap` = `--everything --skip-bootstrap` (workloads + stage-1, bootstrap kept). |

The offline driver test (`tests/test_driver.sh`) locks this behavior down; see [development.md](development.md).

## The identity / key chain

Bootstrap is the day-0 **origin** of every identity used by the toolkit. It always runs with the **org-level owner key** (`.creds/lz-creds.env`), never with a previously generated SA key - it creates those itself:

```text
owner key (.creds/lz-creds.env, day-0, provided by you)
   └─ bootstrap SA + API key   => .creds/lz-<env>-infra-ops.env   (infra-ops project)
   └─ lz-deploy SA + API key   => .creds/lz-<env>.env             (drives stages 1-6)
```

- A key you export in your shell always wins over any `.creds` file.
- **Self-brick guard**: bootstrap's own SA keys cannot destroy bootstrap. It must be destroyed with an org-level key. Its IAM grants would otherwise be revoked mid-run, killing the cleanup (the "self-brick" trap).
- **Post-destroy orphan check**: after any run that destroys stage-1, `destroy.sh` verifies no SG / KMS / Secret / Cockpit resource survived. Scaleway's async/soft-delete can report success while the removal silently fails. The check is scoped to the stage-1 project and excludes bootstrap-owned resources.

## Globally-unique bucket names

Every bootstrap-created bucket gets a frozen timestamp suffix (`<prefix>-<env>-<purpose>-<timestamp>`, timestamp lowercased so the name is S3-valid). The suffix comes from a `time_static` resource, built with `format()` from UTC fields. Each apply produces a fresh name that is never reused - re-creating a bucket after a teardown never collides. `state_bucket_prefix` is a required, validated input.

## Teardown order

`make destroy STAGE=bootstrap` orders its steps so **IAM is deleted last** - one of the hardest-won lessons of this toolkit (see `scripts/destroy.sh`):

1. **State bucket first.** `<prefix>-<env>-terraform-state-<timestamp>` (e.g. `lz-myorg-dev-terraform-state-20261113t091500z`) is Object-Locked (GOVERNANCE, 365d). A locked bucket can ONLY be deleted through the S3 API with `--bypass-governance-retention`. The console/control-plane and the terraform provider both refuse it outright. The only key that can do this is the bootstrap SA key: its default project is the infra-ops project, where the bucket lives (raw S3 follows the key's default project). So the bucket is fully deleted HERE, while that key is still alive. (If your env's bootstrap key was already destroyed without the bucket, recreate a key in the infra-ops project to recover - a plain org key cannot reach it.)
2. **Detach, don't destroy.** Pull the bootstrap IAM (SA app, api_key, org-deploy + iam policies) and the state bucket OUT of the terraform state (`terraform state rm`) before the destroy. Otherwise Terraform's destroy graph revokes the SA keys early - before the bucket/project they reference. That would orphan the locked bucket with no key able to bypass it.
3. **`terraform destroy` then only removes the infra-ops project.**
4. **IAM dies last.** `delete_iam.sh` purges the remaining env-scoped IAM (policies, groups, api keys, applications, SSH keys) as the literal final step. The SA keys outlive every other resource.
