# Scaleway IAM Policy Module

Creates and manages Scaleway IAM Policies with support for rules.

## Usage: Factory-style map (recommended)

Pass a map of policies with principal keys resolved to actual IDs.

```hcl
module "iam_policies" {
  source = "./modules/iam-policy"

  policies = {
    admin_full = {
      name            = "admin-full"
      description     = "Full access for admins"
      group_id        = "group-id-here"
      organization_id = "org-id-here"
      rules = [
        {
          organization_id      = "org-id-here"
          permission_set_names = ["ObjectStorageFullAccess"]
        }
      ]
    }
    cicd_deploy = {
      name            = "cicd-deploy"
      application_id  = "app-id-here"
      organization_id = "org-id-here"
      rules = [
        {
          organization_id      = "org-id-here"
          permission_set_names = ["ObjectStorageObjectsRead", "ObjectStorageObjectsWrite"]
        }
      ]
    }
  }
}
```

## Usage: Legacy single-policy (backward compatible)

```hcl
module "iam_policy" {
  source = "./modules/iam-policy"

  name            = "developers-permissions"
  group_id        = "group-id-here"
  organization_id = "org-id-here"

  rules = [
    {
      project_ids          = ["project-id-here"]
      permission_set_names = ["ObjectStorageReadOnly"]
    }
  ]
}
```

## Inputs

### Factory-style (`policies` map)

The `policies` variable is `type = any` (no strict map(object): avoids null-propagation into provider).

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `name` | `string` | No* | Policy name (defaults to the map key) |
| `description` | `string` | No | Description |
| `tags` | `list(string)` | No | Tags |
| `user_id` | `string` | No | Principal: user ID (one-of) |
| `group_id` | `string` | No | Principal: group ID (one-of) |
| `application_id` | `string` | No | Principal: application ID (one-of) |
| `no_principal` | `bool` | No | No-principal policy (one-of) |
| `organization_id` | `string` | No | Org-level scope |
| `rules` | `list(object)` | Yes* | Rules with `permission_set_names` (required) and optional `project_ids`, `organization_id`, `condition` |

\* `name` falls back to map key; exactly one principal (or `no_principal`) required; at least one rule required.

### Legacy single-policy

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Policy name | `string` | `null` | no |
| `description` | Description | `string` | `null` | no |
| `tags` | Tags | `list(string)` | `[]` | no |
| `organization_id` | Organization ID (org scope) | `string` | `null` | no |
| `user_id` | User principal | `string` | `null` | no |
| `group_id` | Group principal | `string` | `null` | no |
| `application_id` | Service account principal | `string` | `null` | no |
| `no_principal` | No-principal policy | `bool` | `false` | no |
| `rules` | List of rule objects | `list(object)` | `[]` | yes |

## Outputs

| Name | Description |
|------|-------------|
| `ids` | Map of policy IDs keyed by policy key (factory mode) |
| `names` | Map of policy names keyed by policy key (factory mode) |
| `legacy_id` | Policy ID (legacy single-policy mode) |
| `legacy_name` | Policy name (legacy single-policy mode) |
| `id` | Alias for `legacy_id` (backward compat) |
| `name` | Alias for `legacy_name` (backward compat) |

## Principal One-of Rule

Scaleway IAM policies allow exactly ONE principal: `user_id`, `group_id`, `application_id`, or `no_principal`. The module handles this internally:
- If any of `user_id`, `group_id`, or `application_id` is set, only that one is passed to the provider; the rest are nulled.
- If `no_principal: true` is explicitly set and no other principal is defined, it is passed as `true`. Otherwise it's `null`.

## Key Learnings Applied

- `policies` is `type = any` to avoid strict type null-propagation issues
- `lookup()` + `coalesce()` for all optional attributes (never pass `null` under `false`)
- `compact()` on list expressions to avoid empty string elements
- Mutual-exclusive principals computed to pass only exactly one
- Backward-compatible legacy interface preserved
