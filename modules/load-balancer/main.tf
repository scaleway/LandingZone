/**
 * Scaleway Load Balancer Module
 * Creates Load Balancers with IPs, backends, frontends, certificates, and ACLs.
 * ACLs provide WAF-like capabilities (IP filtering, path-based routing, redirects).
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
# Load Balancer IPs
# ---------------------------------------------------------------------------

resource "scaleway_lb_ip" "this" {
  for_each = var.ips

  zone       = var.zone
  project_id = var.project_id
  is_ipv6    = lookup(each.value, "is_ipv6", false)
  reverse    = lookup(each.value, "reverse", null)
}

# ---------------------------------------------------------------------------
# Load Balancer
# ---------------------------------------------------------------------------

resource "scaleway_lb" "this" {
  count = var.create_lb ? 1 : 0

  name        = var.name
  description = var.description
  zone        = var.zone
  project_id  = var.project_id
  type        = var.type
  tags        = var.tags

  ip_ids                  = length(var.ips) > 0 ? [for k, v in var.ips : scaleway_lb_ip.this[k].id] : null
  assign_flexible_ip      = length(var.ips) > 0 ? null : var.assign_flexible_ip
  assign_flexible_ipv6    = length(var.ips) > 0 ? null : var.assign_flexible_ipv6
  ssl_compatibility_level = var.ssl_compatibility_level

  dynamic "private_network" {
    for_each = var.private_networks
    content {
      private_network_id = private_network.value.private_network_id
      ipam_ids           = lookup(private_network.value, "ipam_ids", [])
    }
  }
}

# ---------------------------------------------------------------------------
# Backends
# ---------------------------------------------------------------------------

resource "scaleway_lb_backend" "this" {
  for_each = var.backends

  lb_id                        = scaleway_lb.this[0].id
  name                         = lookup(each.value, "name", each.key)
  forward_protocol             = each.value.forward_protocol
  forward_port                 = each.value.forward_port
  forward_port_algorithm       = lookup(each.value, "forward_port_algorithm", "roundrobin")
  sticky_sessions              = lookup(each.value, "sticky_sessions", "none")
  sticky_sessions_cookie_name  = lookup(each.value, "sticky_sessions_cookie_name", null)
  server_ips                   = lookup(each.value, "server_ips", [])
  proxy_protocol               = lookup(each.value, "proxy_protocol", "none")
  timeout_server               = lookup(each.value, "timeout_server", null)
  timeout_connect              = lookup(each.value, "timeout_connect", null)
  timeout_tunnel               = lookup(each.value, "timeout_tunnel", null)
  failover_host                = lookup(each.value, "failover_host", null)
  ssl_bridging                 = lookup(each.value, "ssl_bridging", false)
  ignore_ssl_server_verify     = lookup(each.value, "ignore_ssl_server_verify", false)
  max_connections              = lookup(each.value, "max_connections", null)
  timeout_queue                = lookup(each.value, "timeout_queue", null)
  redispatch_attempt_count     = lookup(each.value, "redispatch_attempt_count", null)
  max_retries                  = lookup(each.value, "max_retries", null)
  health_check_timeout         = lookup(each.value, "health_check_timeout", null)
  health_check_delay           = lookup(each.value, "health_check_delay", null)
  health_check_port            = lookup(each.value, "health_check_port", null)
  health_check_max_retries     = lookup(each.value, "health_check_max_retries", null)
  on_marked_down_action        = lookup(each.value, "on_marked_down_action", "none")
  health_check_transient_delay = lookup(each.value, "health_check_transient_delay", null)
  health_check_send_proxy      = lookup(each.value, "health_check_send_proxy", false)

  dynamic "health_check_tcp" {
    for_each = lookup(each.value, "health_check_tcp", false) ? [1] : []
    content {}
  }

  dynamic "health_check_http" {
    for_each = lookup(each.value, "health_check_http", null) != null ? [each.value.health_check_http] : []
    content {
      uri         = health_check_http.value.uri
      method      = lookup(health_check_http.value, "method", "GET")
      code        = lookup(health_check_http.value, "code", 200)
      host_header = lookup(health_check_http.value, "host_header", null)
    }
  }

  dynamic "health_check_https" {
    for_each = lookup(each.value, "health_check_https", null) != null ? [each.value.health_check_https] : []
    content {
      uri         = health_check_https.value.uri
      method      = lookup(health_check_https.value, "method", "GET")
      code        = lookup(health_check_https.value, "code", 200)
      host_header = lookup(health_check_https.value, "host_header", null)
      sni         = lookup(health_check_https.value, "sni", null)
    }
  }
}

# ---------------------------------------------------------------------------
# Frontends
# ---------------------------------------------------------------------------

resource "scaleway_lb_frontend" "this" {
  for_each = var.frontends

  lb_id                 = scaleway_lb.this[0].id
  name                  = lookup(each.value, "name", each.key)
  backend_id            = scaleway_lb_backend.this[each.value.backend_key].id
  inbound_port          = each.value.inbound_port
  timeout_client        = lookup(each.value, "timeout_client", null)
  certificate_ids       = lookup(each.value, "certificate_ids", [])
  enable_http3          = lookup(each.value, "enable_http3", false)
  connection_rate_limit = lookup(each.value, "connection_rate_limit", 0)
  enable_access_logs    = lookup(each.value, "enable_access_logs", false)
  external_acls         = true # Use external ACLs for modularity

  depends_on = [scaleway_lb_backend.this]
}

# ---------------------------------------------------------------------------
# ACLs (WAF-like filtering)
# ---------------------------------------------------------------------------

resource "scaleway_lb_acl" "this" {
  for_each = var.acls

  frontend_id = scaleway_lb_frontend.this[each.value.frontend_key].id
  name        = lookup(each.value, "name", each.key)
  description = lookup(each.value, "description", null)
  index       = each.value.index

  action {
    type = each.value.action.type
    dynamic "redirect" {
      for_each = lookup(each.value.action, "redirect", null) != null ? [each.value.action.redirect] : []
      content {
        type   = redirect.value.type
        target = lookup(redirect.value, "target", null)
        code   = lookup(redirect.value, "code", null)
      }
    }
  }

  match {
    ip_subnet          = lookup(each.value.match, "ip_subnet", [])
    ips_edge_services  = lookup(each.value.match, "ips_edge_services", false)
    http_filter        = lookup(each.value.match, "http_filter", null)
    http_filter_value  = lookup(each.value.match, "http_filter_value", null)
    http_filter_option = lookup(each.value.match, "http_filter_option", null)
    invert             = lookup(each.value.match, "invert", false)
  }
}
