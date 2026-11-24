output "id" {
  description = "The unique identifier of the project (UUID format)."
  value       = local.project_id
}

output "name" {
  description = "The name of the Project."
  value       = local.use_existing ? data.scaleway_account_project.existing[0].name : scaleway_account_project.this[0].name
}

output "description" {
  description = "The description of the Project."
  value       = var.description
}

output "created_at" {
  description = "The creation time of the Project."
  value       = local.use_existing ? null : scaleway_account_project.this[0].created_at
}

output "updated_at" {
  description = "The last update time of the Project."
  value       = local.use_existing ? null : scaleway_account_project.this[0].updated_at
}

output "organization_id" {
  description = "The organization ID of the Project."
  value       = var.organization_id
}

output "is_existing" {
  description = "Whether this module references an existing project (true) or created a new one (false)."
  value       = local.use_existing
}

output "iam_policy_ids" {
  description = "Map of IAM policy IDs created inline (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.id }
}

output "iam_policy_names" {
  description = "Map of IAM policy names created inline (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.name }
}

output "iam_policy_count" {
  description = "Number of IAM policies created inline."
  value       = length(var.iam_policies)
}
