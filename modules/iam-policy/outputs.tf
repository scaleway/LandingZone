output "ids" {
  description = "Map of IAM policy IDs (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.id }
}

output "names" {
  description = "Map of IAM policy names (keyed by policy key)."
  value       = { for k, v in scaleway_iam_policy.this : k => v.name }
}

output "legacy_id" {
  description = "The ID of the legacy single policy (only set when per-policy map is empty)."
  value       = local.use_legacy ? scaleway_iam_policy.legacy[0].id : null
}

output "legacy_name" {
  description = "The name of the legacy single policy (only set when per-policy map is empty)."
  value       = local.use_legacy ? scaleway_iam_policy.legacy[0].name : null
}

# Backward-compat aliases, in legacy mode they hold the single policy's id/name;
# in factory mode they are null (use `ids` map instead).
output "id" {
  description = "(LEGACY) The ID of the policy."
  value       = local.use_legacy ? scaleway_iam_policy.legacy[0].id : null
}

output "name" {
  description = "(LEGACY) The name of the IAM policy."
  value       = local.use_legacy ? scaleway_iam_policy.legacy[0].name : null
}
