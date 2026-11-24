output "organization_id" {

  description = "Scaleway Organization ID."
  value       = var.organization_id
}

output "project_ids" {
  description = "Map of created project IDs keyed by project_key."
  value       = { for k, v in module.projects : k => v.id }
}

output "project_names" {
  description = "Map of created project names keyed by project_key."
  value       = { for k, v in module.projects : k => v.name }
}

output "service_account_ids" {
  description = "Map of created service account (application) IDs keyed by sa_key."
  value       = { for k, v in module.service_accounts : k => v.id }
}

output "service_account_names" {
  description = "Map of created service account names keyed by sa_key."
  value       = { for k, v in module.service_accounts : k => v.name }
}

output "iam_group_ids" {
  description = "Map of created IAM group IDs keyed by group_key."
  value       = { for k, v in module.iam_groups : k => v.id }
}

output "iam_group_names" {
  description = "Map of created IAM group names keyed by group_key."
  value       = { for k, v in module.iam_groups : k => v.name }
}

output "iam_policy_ids" {
  description = "Map of created IAM policy IDs keyed by policy_key."
  value       = module.iam_policies.ids
}

output "iam_policy_names" {
  description = "Map of created IAM policy names keyed by policy_key."
  value       = module.iam_policies.names
}

output "vpc_peering_ids" {
  description = "Map of created VPC peering connector IDs keyed by peering_key."

  value = length(local.vpc_peerings) > 0 ? module.vpc_peerings["default"].ids : {}
}

output "vpc_peering_statuses" {
  value = length(local.vpc_peerings) > 0 ? module.vpc_peerings["default"].statuses : {}
}

output "object_bucket_ids" {
  description = "Map of created object storage bucket IDs keyed by bucket_key."
  value       = { for k, v in module.object_buckets : k => v.id }
}

output "object_bucket_names" {
  description = "Map of created object storage bucket names keyed by bucket_key."
  value       = { for k, v in module.object_buckets : k => v.name }
}
