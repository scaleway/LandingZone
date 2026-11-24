/**
 * Scaleway Project Module
 * Creates and manages a Scaleway project within an organization.
 * Supports optional existing-project import via `project_id`.
 * Supports inline IAM policy creation (factory-style `iam_policies` map).
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

# ---------------------------------------------------------------------------
# Local values
# ---------------------------------------------------------------------------
locals {
  # When project_id is provided, reference the existing project via data source.
  # Otherwise, a new project is created.
  use_existing = var.project_id != null

  # Resolve effective project ID
  project_id = local.use_existing ? data.scaleway_account_project.existing[0].id : scaleway_account_project.this[0].id
}

# ---------------------------------------------------------------------------
# Option A: Create new project (project_id not set)
# ---------------------------------------------------------------------------
resource "scaleway_account_project" "this" {
  count = local.use_existing ? 0 : 1

  name            = var.name
  description     = var.description
  organization_id = var.organization_id
}

# ---------------------------------------------------------------------------
# Option B: Reference existing project (project_id set)
# ---------------------------------------------------------------------------
data "scaleway_account_project" "existing" {
  count = local.use_existing ? 1 : 0

  project_id = var.project_id
}

# ---------------------------------------------------------------------------
# IAM Policies - One-call IAM wiring (factory-style map)
# ---------------------------------------------------------------------------
resource "scaleway_iam_policy" "this" {
  for_each = var.iam_policies

  name            = each.value.name
  description     = lookup(each.value, "description", null)
  tags            = concat(var.tags, coalesce(lookup(each.value, "tags", []), []))
  organization_id = var.organization_id

  user_id        = lookup(each.value, "user_id", null)
  group_id       = lookup(each.value, "group_id", null)
  application_id = lookup(each.value, "application_id", null)
  no_principal   = coalesce(lookup(each.value, "no_principal", false), false)

  dynamic "rule" {
    for_each = coalesce(lookup(each.value, "rules", []), [])
    content {
      project_ids          = compact(concat([local.project_id], coalesce(lookup(rule.value, "project_ids", []), [])))
      organization_id      = lookup(rule.value, "organization_id", null)
      permission_set_names = compact(coalesce(lookup(rule.value, "permission_set_names", []), []))
      condition            = lookup(rule.value, "condition", null)
    }
  }
}
