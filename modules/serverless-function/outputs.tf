output "id" {
  description = "ID of the function."
  value       = scaleway_function.this.id
}

output "name" {
  description = "Name of the function."
  value       = scaleway_function.this.name
}

output "namespace_id" {
  description = "ID of the namespace hosting the function."
  value       = local.namespace_id
}

output "namespace_name" {
  description = "Name of the namespace hosting the function."
  value       = var.namespace_id != null ? "external" : scaleway_function_namespace.this[0].name
}

output "domain_name" {
  description = "Default domain name of the function."
  value       = scaleway_function.this.domain_name
}
