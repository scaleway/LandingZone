# ---------------------------------------------------------------------------
# modules/tags - single source of truth for the landing-zone resource tag
# policy. Every stage composes its common tags through this module:
#   - the operator's org policy (fed in as user_tags, e.g. var.common_tags),
#     and
#   - the toolkit-reserved markers that are ALWAYS injected and cannot be
#     overwritten: managed-by / env / stage.
#
# Two forms are exposed because Scaleway resources take tags differently:
#   - output "list": ["compliance=pci-dss", "managed-by=landing-zone-toolkit", ...]
#     for instance-like resources (instances, volumes, IAM, secrets, ...)
#   - output "map":  { compliance = "pci-dss", ... } for object storage buckets
#     (scaleway_object_bucket tags take a map).
#
# Resources must reference these outputs (module.common_tags.list / .map)
# and may append their own per-resource tags on top with concat()/merge().
# The reserved markers always come last/last-merged so a scan of any final
# tag set shows the toolkit's identity on top of the org's own tags.
# ---------------------------------------------------------------------------

locals {
  reserved_list = [
    "managed-by=${var.managed_by}",
    "env=${var.environment}",
    "stage=${var.stage_id}",
  ]
}
