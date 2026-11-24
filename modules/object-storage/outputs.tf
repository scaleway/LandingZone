output "id" {
  description = "ID of the created bucket."
  value       = scaleway_object_bucket.this.id
}

output "name" {
  description = "Name of the created bucket."
  value       = scaleway_object_bucket.this.name
}

output "endpoint" {
  description = "S3-compatible endpoint of the bucket."
  value       = scaleway_object_bucket.this.endpoint
}
