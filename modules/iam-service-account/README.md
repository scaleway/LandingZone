# Scaleway IAM Service Account Module

Creates an IAM Application (service account) and optionally an API key.

## Usage

```hcl
module "service_account" {
  source = "./modules/iam-service-account"

  name        = "ci-cd-app"
  description = "Service account for CI/CD"
  create_api_key = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the IAM application (service account). | `string` | n/a | yes |
| description | The description of the IAM application. | `string` | `null` | no |
| tags | The tags associated with the application. | `list(string)` | `[]` | no |
| organization_id | The ID of the organization the application is associated with. | `string` | `null` | no |
| create_api_key | Whether to create an API key for the application. | `bool` | `true` | no |
| api_key_description | The description of the API key. | `string` | `"API key for service account"` | no |
| api_key_expires_at | The date and time of the expiration of the IAM API key (RFC3339 format). | `string` | `null` | no |
| api_key_default_project_id | The default Project ID to use with Object Storage for the API key. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the application. |
| name | The name of the application. |
| api_key_id | The ID of the API key (access key). |
| access_key | The access key of the IAM API key. (sensitive) |
| secret_key | The secret key of the IAM API key. (sensitive) |
