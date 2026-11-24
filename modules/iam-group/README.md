# Scaleway IAM Group Module

Creates and manages Scaleway IAM Groups and their memberships.

## Usage

```hcl
module "iam_group" {
  source = "./modules/iam-group"

  name        = "developers"
  description = "Group for developers"
  user_ids    = ["user-id-1", "user-id-2"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the IAM group. | `string` | n/a | yes |
| description | The description of the IAM group. | `string` | `null` | no |
| tags | The tags associated with the group. | `list(string)` | `[]` | no |
| application_ids | The list of IDs of the applications attached to the group. | `list(string)` | `[]` | no |
| user_ids | The list of IDs of the users attached to the group. | `list(string)` | `[]` | no |
| organization_id | The ID of the organization the group is associated with. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the IAM group. |
| name | The name of the IAM group. |
