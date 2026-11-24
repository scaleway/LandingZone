output "id" {
  description = "ID of the container."
  value       = scaleway_container.this.id
}

output "name" {
  description = "Name of the container."
  value       = scaleway_container.this.name
}

output "namespace_id" {
  description = "ID of the namespace hosting the container."
  value       = local.namespace_id
}

output "namespace_name" {
  description = "Name of the namespace hosting the container."
  value       = var.namespace_id != null ? "external" : scaleway_container_namespace.this[0].name
}

output "endpoint" {
  description = "Public endpoint of the container (empty when private / not deployed)."
  value       = scaleway_container.this.public_endpoint
}

output "trigger_id" {
  description = "ID of the cron trigger, when enabled."
  value       = var.cron_schedule != null ? scaleway_container_trigger.cron[0].id : null
}
