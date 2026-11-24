output "id" {
  description = "The ID of the application."
  value       = scaleway_iam_application.this.id
}

output "name" {
  description = "The name of the application."
  value       = scaleway_iam_application.this.name
}

output "api_key_id" {
  description = "The ID of the API key (access key)."
  value       = var.create_api_key ? scaleway_iam_api_key.this[0].id : null
}

output "access_key" {
  description = "The access key of the IAM API key."
  value       = var.create_api_key ? scaleway_iam_api_key.this[0].access_key : null
  sensitive   = true
}

output "secret_key" {
  description = "The secret key of the IAM API key."
  value       = var.create_api_key ? scaleway_iam_api_key.this[0].secret_key : null
  sensitive   = true
}
