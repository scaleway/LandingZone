# Stage 4 - Project Factory

Creates per-team projects (apps, data, ...), each with its own VPC, service
accounts, IAM groups, IAM policies, hub peering, and object-storage buckets.

## What to edit

- **`envs/<env>/data/projects-<env>.yaml`**: everything this stage creates:
  projects, service accounts, IAM groups/policies, peerings, buckets.
- **`envs/<env>/4-project-factory-<env>.tfvars`**: org ID, parent project,
  region, zone.

## Usage

```bash
make apply STAGE=4 [ENV=<env>]     # or: terraform init/plan/apply in this dir
```

Optional stage: skipped when the per-env tfvars are absent.

## Modules

- `modules/project`: project + VPC + private network
- `modules/iam-service-account`, `modules/iam-group`, `modules/iam-policy`
- `modules/object-storage`, `modules/vpc-peering`
