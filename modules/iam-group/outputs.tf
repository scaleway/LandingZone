output "id" {
  description = "The ID of the IAM group."
  value       = scaleway_iam_group.this.id
}

output "name" {
  description = "The name of the IAM group."
  value       = scaleway_iam_group.this.name
}
