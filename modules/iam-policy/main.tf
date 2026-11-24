/**
 * Scaleway IAM Policy Module, Factory-style map interface
 *
 * Creates and manages Scaleway IAM Policies with support for rules.
 *
 * Two interfaces supported:
 *   1. Factory-style map (recommended): pass `policies = { <key> = { ... } }`
 *   2. Legacy single-policy: pass name/description/tags/rules/principal as before
 *
 * Key learnings applied (from project module):
 *   - `policies` is `type = any` (avoids null-propagation into provider)
 *   - `lookup()` + `coalesce()` for ALL optional attributes
 *   - `compact()` on list expressions (permission_set_names, project_ids)
 *   - Avoid strict `map(object({... optional()}))` types
 */

terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }
}

# --------------------------------------------------------------------------
# Legacy single-policy interface, preserve original behavior
# --------------------------------------------------------------------------
locals {
  # If `policies` is empty, fall back to legacy single-policy interface.
  use_legacy = length(var.policies) == 0
}

# --------------------------------------------------------------------------
# Policy resources, factory map interface (recommended)
# --------------------------------------------------------------------------
resource "scaleway_iam_policy" "this" {
  for_each = var.policies

  name        = lookup(each.value, "name", each.key)
  description = coalesce(lookup(each.value, "description", null), null)
  tags        = compact(coalesce(lookup(each.value, "tags", []), []))
  # Default organization_id from legacy var if not set per-policy
  organization_id = coalesce(lookup(each.value, "organization_id", null), var.organization_id, null)

  user_id        = lookup(each.value, "user_id", null)
  group_id       = lookup(each.value, "group_id", null)
  application_id = lookup(each.value, "application_id", null)

  # Only pass no_principal=true when explicitly set AND no other principal
  # is provided. Otherwise keep it null so the provider doesn't complain
  # about multiple principals being set.
  no_principal = (
    coalesce(lookup(each.value, "no_principal", false), false) ? true : null
  )

  dynamic "rule" {
    for_each = coalesce(lookup(each.value, "rules", []), [])
    content {
      project_ids = compact(coalesce(lookup(rule.value, "project_ids", []), []))
      # Rule-level organization_id defaults to the entry's when the rule does
      # not set one. An explicit null (rule-level or entry-level) yields an
      # org-less rule, which is required for project-scoped rules: the API
      # rejects a rule carrying both an org scope and project_ids.
      organization_id      = lookup(rule.value, "organization_id", each.value.organization_id)
      permission_set_names = compact(coalesce(lookup(rule.value, "permission_set_names", []), []))
      condition            = lookup(rule.value, "condition", null)
    }
  }
}

# --------------------------------------------------------------------------
# Legacy single-policy resource (kept for backward compatibility)
# --------------------------------------------------------------------------
resource "scaleway_iam_policy" "legacy" {
  count = local.use_legacy ? 1 : 0

  name            = var.name
  description     = var.description
  tags            = compact(var.tags)
  organization_id = var.organization_id

  user_id        = var.user_id
  group_id       = var.group_id
  application_id = var.application_id
  # Only pass no_principal=true when explicitly set AND no other principal
  no_principal = (
    var.no_principal &&
    var.user_id == null &&
    var.group_id == null &&
    var.application_id == null
  ) ? true : null

  dynamic "rule" {
    for_each = coalesce(var.rules, [])
    content {
      project_ids          = compact(coalesce(lookup(rule.value, "project_ids", []), []))
      organization_id      = lookup(rule.value, "organization_id", null)
      permission_set_names = compact(coalesce(lookup(rule.value, "permission_set_names", []), []))
      condition            = lookup(rule.value, "condition", null)
    }
  }
}

