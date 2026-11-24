/**
 * Scaleway DNS Module
 * Creates DNS zones and records.
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

resource "scaleway_domain_zone" "zones" {
  for_each   = var.zones
  domain     = each.value.domain
  subdomain  = each.value.subdomain
  project_id = var.project_id
}

resource "scaleway_domain_record" "records" {
  for_each = var.records

  dns_zone = scaleway_domain_zone.zones[each.value.zone_key].id
  name     = each.value.name
  type     = each.value.type
  data     = each.value.data
  ttl      = lookup(each.value, "ttl", 3600)
  priority = lookup(each.value, "priority", 0)
}