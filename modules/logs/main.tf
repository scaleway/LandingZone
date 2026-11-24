/**
 * Logs / Observability Module
 * Creates Scaleway Cockpit data sources (metrics, logs, traces) and access tokens.
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
# Cockpit Data Sources
# ---------------------------------------------------------------------------

resource "scaleway_cockpit_source" "this" {
  for_each = var.sources

  name           = each.value.name
  type           = each.value.type
  project_id     = var.project_id
  region         = var.region
  retention_days = each.value.retention_days
}

# ---------------------------------------------------------------------------
# Cockpit Tokens
# ---------------------------------------------------------------------------

resource "scaleway_cockpit_token" "this" {
  for_each = var.tokens

  name       = each.value.name
  project_id = var.project_id
  region     = var.region

  dynamic "scopes" {
    for_each = each.value.scopes != null ? [each.value.scopes] : []
    content {
      query_metrics       = lookup(scopes.value, "query_metrics", false)
      write_metrics       = lookup(scopes.value, "write_metrics", true)
      setup_metrics_rules = lookup(scopes.value, "setup_metrics_rules", false)
      query_logs          = lookup(scopes.value, "query_logs", false)
      write_logs          = lookup(scopes.value, "write_logs", true)
      setup_logs_rules    = lookup(scopes.value, "setup_logs_rules", false)
      setup_alerts        = lookup(scopes.value, "setup_alerts", false)
      query_traces        = lookup(scopes.value, "query_traces", false)
      write_traces        = lookup(scopes.value, "write_traces", false)
    }
  }
}