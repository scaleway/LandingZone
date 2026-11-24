/**
 * Scaleway Instance VM Module
 * Creates compute instances with reserved IPs, security groups, and private networks.
 * Supports cloud-init user data for boot-time configuration.
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
# Reserved IPs
# ---------------------------------------------------------------------------

resource "scaleway_instance_ip" "this" {
  for_each = var.ips

  zone       = var.zone
  project_id = var.project_id
}

# ---------------------------------------------------------------------------
# Static (pinned) private IPs, one IPAM reservation per PN that requested
# one; NICs fall back to DHCP when `ipam_ip` is null.
# ---------------------------------------------------------------------------

resource "scaleway_ipam_ip" "static" {
  for_each = { for k, v in var.private_networks : k => v if v.ipam_ip != null }

  address    = each.value.ipam_ip
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = each.value.pn_id
  }
}

# ---------------------------------------------------------------------------
# Instance Server
# ---------------------------------------------------------------------------

resource "scaleway_instance_server" "this" {
  count = var.create_instance ? 1 : 0

  name               = var.name
  type               = var.instance_type
  image              = var.image
  zone               = var.zone
  project_id         = var.project_id
  tags               = var.tags
  security_group_id  = var.security_group_id
  placement_group_id = var.placement_group_id
  enable_dynamic_ip  = var.enable_dynamic_ip
  state              = var.state
  boot_type          = var.boot_type
  protected          = var.protected

  ip_ids = concat([for k, v in var.ips : scaleway_instance_ip.this[k].id], var.existing_ip_ids)

  dynamic "root_volume" {
    for_each = var.root_volume != null ? [var.root_volume] : []
    content {
      size_in_gb            = lookup(root_volume.value, "size_in_gb", null)
      volume_type           = lookup(root_volume.value, "volume_type", null)
      delete_on_termination = lookup(root_volume.value, "delete_on_termination", true)
      sbs_iops              = lookup(root_volume.value, "sbs_iops", null)
      volume_id             = lookup(root_volume.value, "volume_id", null)
    }
  }

  additional_volume_ids = var.additional_volume_ids
  user_data             = var.user_data

  # No inline private_network blocks, every PN attaches via standalone NICs
  # below (see the pnics_teardown comment for why).
}

# ---------------------------------------------------------------------------
# Standalone NICs, one per private network (DHCP or pinned). The inline
# private_network block has no IPAM argument in this provider (pins are
# impossible) and its server-destroy detach loop can't delete a pnic on
# gateway-managed PNs, so standalone NICs + the destroy-time pnics_teardown
# helper below keep `terraform destroy` a single command.
# ---------------------------------------------------------------------------
resource "scaleway_instance_private_nic" "this" {
  for_each = var.create_instance ? var.private_networks : {}

  server_id          = scaleway_instance_server.this[0].id
  private_network_id = each.value.pn_id
  ipam_ip_ids        = each.value.ipam_ip != null ? [scaleway_ipam_ip.static[each.key].id] : null
  zone               = var.zone
}

# ---------------------------------------------------------------------------
# Destroy-time teardown helper. Each NIC depends on the server, and the v2 API
# rejects deleting a pnic while its server runs, so plain destroy would fail.
# This resource is destroyed first (its `when = destroy` provisioner removes
# all pnics via the CLI, idempotently), after which NIC / IPAM / server delete
# cleanly, `terraform destroy` / `-replace` stays a single command.
# ---------------------------------------------------------------------------
resource "null_resource" "pnics_teardown" {
  count = var.create_instance && length(var.private_networks) > 0 ? 1 : 0

  depends_on = [
    scaleway_instance_server.this,
    # Whole-resource refs, safe when for_each is empty.
    scaleway_instance_private_nic.this,
    scaleway_ipam_ip.static,
  ]

  triggers = {
    server_uuid = split("/", scaleway_instance_server.this[0].id)[1]
    # Server-resolved zone, not var.zone (may be null / provider-defaulted):
    # the destroy provisioner must query the zone the server actually lives in.
    zone = scaleway_instance_server.this[0].zone
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      SRV="${self.triggers.server_uuid}"
      ZONE="${self.triggers.zone}"
      for ATTEMPT in 1 2 3; do
        PIDS=$(scw instance private-nic list server-id=$SRV zone=$ZONE -o json 2>/dev/null \
            | grep -oE '"id":"[0-9a-f-]{36}"' | cut -d'"' -f4)
        if [ -z "$PIDS" ]; then
          break
        fi
        for P in $PIDS; do
          scw instance private-nic delete server-id=$SRV private-nic-id=$P zone=$ZONE 2>&1 || true
        done
        sleep 2
      done
    EOT
  }
}
