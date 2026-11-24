# Stage 1 - Security

Centralized security: IAM policies, Cockpit observability, KMS keys,
Secret Manager secrets, and security groups.

## What to edit

- **`envs/<env>/data/security-<env>.yaml`**: everything this stage creates
  (cockpit, KMS keys, secrets, security groups).
- **`envs/<env>/1-security-<env>.tfvars`**: org ID, region, zone, project.

The YAML is loaded with `yamldecode()` and turned into resources with
`for_each`. You can override any resource by defining the same key in tfvars
(the tfvars value wins via `merge()`), without touching the shared YAML.

## Usage

```bash
make apply STAGE=1 [ENV=<env>]     # or: terraform init/plan/apply in this dir
```

## Modules

- `modules/iam-policy`: IAM policies bound to bootstrap groups/SAs
- `modules/logs`: Cockpit (metrics, logs, traces) with tokens
- `modules/kms`: KMS encryption keys
- `modules/secrets`: Secret Manager entries
- `modules/security-group`: Instance security groups for VMs
