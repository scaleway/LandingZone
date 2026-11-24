# Scaleway Project Module

Creates and manages a Scaleway project within an organization.

## Features

- **Create new project** (default): uses `scaleway_account_project`
- **Reference existing project**: pass `project_id` to manage an existing project (uses `data.scaleway_account_project`)
- **Inline IAM policies**: provide `iam_policies` map to create policies scoped to the project in a single module call
- **Tags**: propagated to inline IAM policies (the `scaleway_account_project` resource does not support tags natively)

## Usage

### Create a new project

```hcl
module "project" {
  source = "./modules/project"

  name            = "my-project"
  description     = "Project for team X"
  organization_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  tags            = ["team-a", "production"]
}
```

### Reference an existing project (import pattern)

```hcl
module "existing_project" {
  source = "./modules/project"

  name            = "my-existing-project"
  project_id      = "11111111-1111-1111-1111-111111111111"
  organization_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

### One-call IAM wiring

```hcl
module "project" {
  source = "./modules/project"

  name            = "my-project"
  organization_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

  iam_policies = {
    admins_full = {
      name     = "lz-dev-admins-full"
      group_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      rules = [
        {
          organization_id      = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
          permission_set_names = ["InstancesFullAccess", "ObjectStorageFullAccess"]
        }
      ]
    }
    developers_ro = {
      name           = "lz-dev-developers-ro"
      application_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
      description    = "Read-only for developers"
      rules = [
        {
          permission_set_names = ["InstancesReadOnly", "ObjectStorageObjectsRead"]
        }
      ]
    }
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the Project. | `string` | n/a | yes |
| description | The description of the Project. | `string` | `null` | no |
| organization_id | The organization ID the Project is associated with. | `string` | `null` | no |
| project_id | Optional existing project ID to reference instead of creating new. | `string` | `null` | no |
| tags | Tags to apply to resources created by this module (propagated to inline IAM policies). | `list(string)` | `[]` | no |
| iam_policies | Map of IAM policies to create alongside the project. | `any` | `{}` | no |

### `iam_policies` object schema (documented contract)

> Note: the variable is declared as `any` to avoid Terraform null-propagation issues with strict `map(object(...))` types. Use the schema below as the contract for the values you provide.

```hcl
{
  name           = string
  description    = optional(string)
  tags           = optional(list(string), [])
  user_id        = optional(string)
  group_id       = optional(string)
  application_id = optional(string)
  no_principal   = optional(bool, false)
  rules = [{
    project_ids          = optional(list(string))
    organization_id      = optional(string)
    permission_set_names = list(string)
    condition            = optional(string)
  }]
}
```

## Outputs

| Name | Description |
|------|-------------|
| id | The unique identifier of the project (UUID format). |
| name | The name of the Project. |
| description | The description of the Project. |
| created_at | The creation time of the Project (null when referencing existing). |
| updated_at | The last update time of the Project (null when referencing existing). |
| organization_id | The organization ID of the Project. |
| is_existing | Whether this module references an existing project (true) or created a new one (false). |
| iam_policy_ids | Map of IAM policy IDs created inline (keyed by policy key). |
| iam_policy_names | Map of IAM policy names created inline (keyed by policy key). |
| iam_policy_count | Number of IAM policies created inline. |

## Notes

- The `scaleway_account_project` resource (provider v2.x) does **not** natively support `tags` or an import attribute.
  - `tags` are propagated to inline IAM policies created by this module.
  - For existing project management, use the `project_id` data-source pattern.
- When `project_id` is set, the module will **not** create a new project resource, but will reference the existing project via `data.scaleway_account_project`.
- IAM policy rules automatically include the project ID in `project_ids`: you only need to specify additional project IDs if needed."