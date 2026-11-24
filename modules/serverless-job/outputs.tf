output "id" {
  description = "ID of the Job definition."
  value       = scaleway_job_definition.this.id
}

output "name" {
  description = "Name of the Job definition."
  value       = scaleway_job_definition.this.name
}

output "region" {
  description = "Region of the Job definition."
  value       = scaleway_job_definition.this.region
}

output "cpu_limit" {
  description = "CPU limit of the Job definition in mCPU."
  value       = scaleway_job_definition.this.cpu_limit
}

output "memory_limit" {
  description = "Memory limit of the Job definition in MiB."
  value       = scaleway_job_definition.this.memory_limit
}
