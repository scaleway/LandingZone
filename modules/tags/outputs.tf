output "list" {
  description = "Common tags as a list of key=value strings (instance-like resources): org tags first, toolkit-reserved markers last."
  value = concat(
    [for k, v in var.user_tags : "${k}=${v}"],
    local.reserved_list,
  )
}

output "map" {
  description = "Common tags as a map (object storage buckets): org tags merged with the toolkit-reserved markers."
  value = merge(
    var.user_tags,
    {
      "managed-by" = var.managed_by
      environment  = var.environment
      stage        = var.stage_id
    },
  )
}
