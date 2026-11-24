# tags

Single source of truth for the landing-zone resource tag policy.

Every toolkit stage composes its common tags through this module instead of
repeating the composition inline: the operator's own tag policy
(`var.common_tags`, fed in as `user_tags`) plus the **toolkit-reserved
markers** that are always injected and can never be overwritten:

| Tag | Value | Purpose |
|-----|-------|---------|
| `managed-by` | `landing-zone-toolkit` | Identify toolkit-owned resources for cleanup, filtering and drift checks |
| `env` | the environment (`dev`, `prod`) | Per-environment filtering |
| `stage` | the stage id (`stage1` … `bootstrap`) | Per-stage attribution |

Trying to set any of those three keys in `var.common_tags` fails validation;
keys/values containing `=` or `:` are rejected too (Scaleway tag format is
`key=value` and the platform rejects `:` in IAM tag values).

## Usage

```hcl
module "common_tags" {
  source      = "../../modules/tags"
  user_tags   = var.common_tags   # the org's own tag policy, default {}
  environment = local.environment # or var.environment, depending on the stage
  stage_id    = "stage3"          # "bootstrap" for the bootstrap stage
}

locals {
  # Instances, volumes, IAM, secrets, ... take a list of key=value strings.
  common_tags = module.common_tags.list
  # Object storage buckets take a map.
  common_tags_map = module.common_tags.map
}

# Optionally append per-resource tags on top:
resource "scaleway_instance_server" "web" {
  # ...
  tags = concat(local.common_tags, ["web", "frontend"])
}

resource "scaleway_object_bucket" "data" {
  # ...
  tags = merge(local.common_tags_map, { purpose = "data" })
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `user_tags` | `map(string)` | no (`{}`) | Org-wide tags, validated: no `=`/`:`, reserved keys rejected |
| `environment` | `string` | yes | Environment name, injected as the `env` marker |
| `stage_id` | `string` | yes | Stage id, injected as the `stage` marker |
| `managed_by` | `string` | no (`landing-zone-toolkit`) | Value of the `managed-by` marker |

## Outputs

| Name | Description |
|------|-------------|
| `list` | Common tags as `["k=v", ...]` (instance-like resources) |
| `map`  | Common tags as a map (object storage buckets) |
