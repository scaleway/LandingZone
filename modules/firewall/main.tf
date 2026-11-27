# ---------------------------------------------------------------------------
# HA-Firewall Module, Vendor-agnostic HA Firewall Deployment
#
# Ported from the proven OPNsense implementation at /HA-firewalls/opnsense-HA.
# Parameterized for the CARP vendor:
#   vendor = "opnsense"   => CARP-based HA (virtual IPs with custom MACs)
#
# Other vendors (pfsense/fortigate/paloalto/stormshield) are planned add-ons
# (tracked as GitHub issues) and are not wired in this module.
#
# Expects VPCs/PNs to be created by the caller (Stage 3 root module).
#
# WARNING: NIC ATTACHMENT ORDER (OPNsense, positional vtnet mapping)
#   OPNsense maps vtnet0..vtnet3 from the *actual order* the private NICs are
#   attached to the server:
#     vtnet0 = wan      (default/mgmt, born with the server, no PN)
#     vtnet1 = lan      (hub PN)      => 1st PN attached
#     vtnet2 = opt1     (sync PN)     => 2nd PN attached
#     vtnet3 = opt2     (egress PN)   => 3rd PN attached (only in PGW mode)
#   The depends_on chain below (*_lan => *_ha [=> *_wan]) guarantees the
#   attachment order. DO NOT reorder the NIC resources and do not refactor
#   them into a for_each map (map iteration order is not preserved reliably
#   by Terraform).
#
#   Flexible-IP mode (wan_private_network_ids empty): the WAN is the routed
#   main NIC (vtnet0) with a flexible public IP attached via ip_ids, and only
#   LAN + sync private NICs are created (vtnet1 / vtnet2).
# ---------------------------------------------------------------------------

locals {
  _snapshot_zones = keys(var.snapshot_ids)

  # Resolve fw_passive/fw_active zones: explicit var.zones wins, else derive from the
  # snapshot_ids map keys (first key = fw_passive, second = fw_active).
  zones = {
    fw_passive = var.zones.fw_passive != null ? var.zones.fw_passive : local._snapshot_zones[0]
    fw_active  = var.zones.fw_active != null ? var.zones.fw_active : try(local._snapshot_zones[1], local._snapshot_zones[0])
  }

  # Resource name prefix - lz-<env> keeps naming consistent with the rest of
  # the toolkit (stage resources all use lz-<environment>-...).
  name_prefix = "lz-${var.environment}"

  # CARP vendor uses virtual IPs (opnsense)
  is_carp = var.vendor == "opnsense"

  # WAN private network is optional. When none is provided the WAN is the
  # routed main NIC (vtnet0) with a flexible public IP (see fw_passive_ip_id/
  # fw_active_ip_id), no egress private NIC is created. The variable contract
  # states: "Empty list => flexible-IP WAN", so the list itself is the source
  # of truth.
  # wan_enabled must be decidable at PLAN time on a from-scratch apply AND
  # during `terraform import`: the WAN PN is created in the same plan
  # (e.g. module.vpc_egress), so its *ID*, and the presence of a matching
  # *key* in a module-output map, is unknown until apply ("Invalid count
  # argument ... cannot be determined until apply"). The list length is
  # always known.
  wan_primary_pn_key = length(var.wan_pn_keys) > 0 ? var.wan_pn_keys[0] : null
  wan_enabled        = length(var.wan_pn_keys) > 0
  wan_primary_pn_id  = local.wan_primary_pn_key != null ? lookup(var.wan_private_network_ids, local.wan_primary_pn_key, null) : null

  # Reference to the LAN (hub) PN the firewall pair attaches to
  lan_pn_id = var.lan_private_network_ids[var.lan_pn_key]
  ha_pn_id  = var.ha_private_network_ids[var.ha_pn_key]
}

# ---------------------------------------------------------------------------
# IPAM IPs, Firewall 1
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "fw_passive_wan" {
  count = local.wan_enabled ? 1 : 0

  address    = var.fw_passive_ips.wan
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.wan_primary_pn_id
  }
}

resource "scaleway_ipam_ip" "fw_passive_lan" {
  address    = var.fw_passive_ips.lan
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.lan_pn_id
  }
}

resource "scaleway_ipam_ip" "fw_passive_ha" {
  address    = var.fw_passive_ips.ha
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.ha_pn_id
  }
  depends_on = [scaleway_ipam_ip.fw_passive_lan]
}

# ---------------------------------------------------------------------------
# IPAM IPs, Firewall 2
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "fw_active_wan" {
  count = local.wan_enabled ? 1 : 0

  address    = var.fw_active_ips.wan
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.wan_primary_pn_id
  }
}

resource "scaleway_ipam_ip" "fw_active_lan" {
  address    = var.fw_active_ips.lan
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.lan_pn_id
  }
}

resource "scaleway_ipam_ip" "fw_active_ha" {
  address    = var.fw_active_ips.ha
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.ha_pn_id
  }
  depends_on = [scaleway_ipam_ip.fw_active_lan]
}

# ---------------------------------------------------------------------------
# CARP Virtual IPs (only for opnsense)
# The MAC addresses must match the CARP vhid used in the OPNsense config
# (00:00:5e:00:01:<vhid>). Override via vip_wan_mac / vip_lan_mac.
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "vip_wan" {
  count = local.is_carp && var.enable_vips && var.vip_ips.wan != null ? 1 : 0

  address    = var.vip_ips.wan
  is_ipv6    = false
  project_id = var.project_id
  custom_resource {
    mac_address = var.vip_wan_mac
  }
  source {
    private_network_id = local.wan_primary_pn_id
  }
}

resource "scaleway_ipam_ip" "vip_lan" {
  count = local.is_carp && var.enable_vips ? 1 : 0

  address    = var.vip_ips.lan
  is_ipv6    = false
  project_id = var.project_id
  custom_resource {
    mac_address = var.vip_lan_mac
  }
  source {
    private_network_id = local.lan_pn_id
  }
}

# ---------------------------------------------------------------------------
# Image-identity guards: the root volumes live in modules/firewall-image, so
# this module cannot reference them directly (replace_triggered_by only
# accepts resource references, not module variables). Each guard mirrors the
# image-derived volume ID; when a golden image rotates it (snapshot -> volume
# rebuild upstream), the guard is replaced and forces the instance to rebuild.
# A config-only change (extra_user_data / XML) never touches these - no rebuild.
# ---------------------------------------------------------------------------
resource "terraform_data" "fw_passive_root_volume" {
  triggers_replace = {
    volume_id = var.snapshot_ids[local.zones.fw_passive].volume_id
  }
}

resource "terraform_data" "fw_active_root_volume" {
  triggers_replace = {
    volume_id = var.snapshot_ids[local.zones.fw_active].volume_id
  }
}

# ---------------------------------------------------------------------------
# Firewall instances
# ---------------------------------------------------------------------------
resource "scaleway_instance_server" "fw_passive" {
  boot_type  = "local"
  name       = "${local.name_prefix}-${var.vendor}-fw-passive"
  type       = var.instance_type
  zone       = local.zones.fw_passive
  project_id = var.project_id
  # Instance security groups are zone-scoped: prefer a per-node SG ("fw_passive"),
  # fall back to the legacy single-SG key for backward compatibility.
  security_group_id = try(var.security_group_ids["fw_passive"], var.security_group_ids["firewall_mgmt"], null)
  tags              = concat(var.tags, [var.vendor, "fw_passive"])

  # Flexible-IP mode: the WAN is the routed main NIC (vtnet0) with this
  # public IP; OPNsense WAN = vtnet0 DHCP.
  ip_ids = var.fw_passive_ip_id != null ? [var.fw_passive_ip_id] : []

  # OPNsense (CARP) config is injected through the native
  # user_data "opnsense_config" key (base64 XML); the appliance imports it
  # on first boot (same mechanism as the blueprint firewall-ha).
  # var.extra_user_data_passive merges in additional keys (cloud-init etc.)
  # without touching the XML - a clean channel for per-node tweaks that must
  # not re-render/re-import (and reboot) the HA pair.
  user_data = merge(
    {
      opnsense_config = base64encode(local.fw_passive_xml)
    },
    var.extra_user_data_passive,
  )

  root_volume {
    boot                  = true
    delete_on_termination = true
    size_in_gb            = var.snapshot_ids[local.zones.fw_passive].size_gb
    volume_id             = var.snapshot_ids[local.zones.fw_passive].volume_id
    volume_type           = "sbs_volume"
  }

  # A new golden image rotates the root volume ID (snapshot -> volume rebuild)
  # upstream in modules/firewall-image. The provider would otherwise treat a
  # root_volume volume_id swap as an in-place update - but the disk (and its
  # boot image) actually changes, so force a full node replacement. terraform_data
  # turns the (value-only) var into a replace_triggered_by-visible resource keyed
  # on the image-derived volume ID.
  lifecycle {
    replace_triggered_by = [
      terraform_data.fw_passive_root_volume,
    ]
  }
}

# NICs, LAN (hub) FIRST, then HA (sync), then WAN (egress).
# This positional order maps to OPNsense vtnet1 / vtnet2 / vtnet3. Never reorder.
resource "scaleway_instance_private_nic" "fw_passive_lan" {
  private_network_id = local.lan_pn_id
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_passive_lan.id]
  zone               = local.zones.fw_passive
}

resource "scaleway_instance_private_nic" "fw_passive_ha" {
  private_network_id = local.ha_pn_id
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_passive_ha.id]
  zone               = local.zones.fw_passive
  depends_on         = [scaleway_instance_private_nic.fw_passive_lan]
}

resource "scaleway_instance_private_nic" "fw_passive_wan" {
  count = local.wan_enabled ? 1 : 0

  private_network_id = local.wan_primary_pn_id
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_passive_wan[0].id]
  zone               = local.zones.fw_passive
  depends_on         = [scaleway_instance_private_nic.fw_passive_ha]
}

resource "scaleway_instance_server" "fw_active" {
  boot_type  = "local"
  name       = "${local.name_prefix}-${var.vendor}-fw-active"
  type       = var.instance_type
  zone       = local.zones.fw_active
  project_id = var.project_id
  # Instance security groups are zone-scoped: prefer a per-node SG ("fw_active"),
  # fall back to the legacy single-SG key for backward compatibility.
  security_group_id = try(var.security_group_ids["fw_active"], var.security_group_ids["firewall_mgmt"], null)
  tags              = concat(var.tags, [var.vendor, "fw_active"])

  # Flexible-IP mode: the WAN is the routed main NIC (vtnet0) with this
  # public IP; OPNsense WAN = vtnet0 DHCP.
  ip_ids = var.fw_active_ip_id != null ? [var.fw_active_ip_id] : []

  # Same as fw_passive: XML via opnsense_config, plus per-node extra
  # user-data keys (cloud-init etc.) merged in - no XML re-render/reboot.
  user_data = merge(
    {
      opnsense_config = base64encode(local.fw_active_xml)
    },
    var.extra_user_data_active,
  )

  root_volume {
    boot                  = true
    delete_on_termination = true
    size_in_gb            = var.snapshot_ids[local.zones.fw_active].size_gb
    volume_id             = var.snapshot_ids[local.zones.fw_active].volume_id
    volume_type           = "sbs_volume"
  }

  # A new golden image rotates the root volume ID (snapshot -> volume rebuild)
  # upstream in modules/firewall-image. The provider would otherwise treat a
  # root_volume volume_id swap as an in-place update - but the disk (and its
  # boot image) actually changes, so force a full node replacement. terraform_data
  # turns the (value-only) var into a replace_triggered_by-visible resource keyed
  # on the image-derived volume ID.
  lifecycle {
    replace_triggered_by = [
      terraform_data.fw_active_root_volume,
    ]
  }
}

resource "scaleway_instance_private_nic" "fw_active_lan" {
  private_network_id = local.lan_pn_id
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_active_lan.id]
  zone               = local.zones.fw_active
}

resource "scaleway_instance_private_nic" "fw_active_ha" {
  private_network_id = local.ha_pn_id
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_active_ha.id]
  zone               = local.zones.fw_active
  depends_on         = [scaleway_instance_private_nic.fw_active_lan]
}

resource "scaleway_instance_private_nic" "fw_active_wan" {
  count = local.wan_enabled ? 1 : 0

  private_network_id = local.wan_primary_pn_id
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_active_wan[0].id]
  zone               = local.zones.fw_active
  depends_on         = [scaleway_instance_private_nic.fw_active_ha]
}

# ---------------------------------------------------------------------------
# Optional second HA network (generic second sync network)
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "fw_passive_ha2" {
  count = length(var.ha2_private_network_ids) > 0 ? 1 : 0

  address    = var.fw_passive_ips.ha2
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = lookup(var.ha2_private_network_ids, var.ha2_pn_key, null)
  }
  depends_on = [scaleway_ipam_ip.fw_passive_ha]
}

resource "scaleway_instance_private_nic" "fw_passive_ha2" {
  count = length(var.ha2_private_network_ids) > 0 ? 1 : 0

  private_network_id = lookup(var.ha2_private_network_ids, var.ha2_pn_key, null)
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = try([scaleway_ipam_ip.fw_passive_ha2[0].id], [])
  zone               = local.zones.fw_passive
  depends_on         = [scaleway_instance_private_nic.fw_passive_ha]
}

resource "scaleway_ipam_ip" "fw_active_ha2" {
  count = length(var.ha2_private_network_ids) > 0 ? 1 : 0

  address    = var.fw_active_ips.ha2
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = lookup(var.ha2_private_network_ids, var.ha2_pn_key, null)
  }
  depends_on = [scaleway_ipam_ip.fw_active_ha]
}

resource "scaleway_instance_private_nic" "fw_active_ha2" {
  count = length(var.ha2_private_network_ids) > 0 ? 1 : 0

  private_network_id = lookup(var.ha2_private_network_ids, var.ha2_pn_key, null)
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = try([scaleway_ipam_ip.fw_active_ha2[0].id], [])
  zone               = local.zones.fw_active
  depends_on         = [scaleway_instance_private_nic.fw_active_ha]
}

# ---------------------------------------------------------------------------
# Optional management network (generic optional attachment)
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "fw_passive_mgmt" {
  count = length(var.management_private_network_ids) > 0 ? 1 : 0

  address    = var.fw_passive_ips.mgmt
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = lookup(var.management_private_network_ids, var.management_pn_key, null)
  }
  depends_on = [scaleway_ipam_ip.fw_passive_ha]
}

resource "scaleway_instance_private_nic" "fw_passive_mgmt" {
  count = length(var.management_private_network_ids) > 0 ? 1 : 0

  private_network_id = lookup(var.management_private_network_ids, var.management_pn_key, null)
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = try([scaleway_ipam_ip.fw_passive_mgmt[0].id], [])
  zone               = local.zones.fw_passive
  depends_on         = [scaleway_instance_private_nic.fw_passive_ha]
}

resource "scaleway_ipam_ip" "fw_active_mgmt" {
  count = length(var.management_private_network_ids) > 0 ? 1 : 0

  address    = var.fw_active_ips.mgmt
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = lookup(var.management_private_network_ids, var.management_pn_key, null)
  }
  depends_on = [scaleway_ipam_ip.fw_active_ha]
}

resource "scaleway_instance_private_nic" "fw_active_mgmt" {
  count = length(var.management_private_network_ids) > 0 ? 1 : 0

  private_network_id = lookup(var.management_private_network_ids, var.management_pn_key, null)
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = try([scaleway_ipam_ip.fw_active_mgmt[0].id], [])
  zone               = local.zones.fw_active
  depends_on         = [scaleway_instance_private_nic.fw_active_ha]
}

# ---------------------------------------------------------------------------
# Optional second WAN network (dual-WAN vendors)
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "fw_passive_wan2" {
  count = length(var.wan_pn_keys) > 1 ? 1 : 0

  address    = var.fw_passive_ips.wan2
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = var.wan_private_network_ids[var.wan_pn_keys[1]]
  }
  depends_on = [scaleway_ipam_ip.fw_passive_ha]
}

resource "scaleway_instance_private_nic" "fw_passive_wan2" {
  count = length(var.wan_pn_keys) > 1 ? 1 : 0

  private_network_id = var.wan_private_network_ids[var.wan_pn_keys[1]]
  server_id          = scaleway_instance_server.fw_passive.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_passive_wan2[0].id]
  zone               = local.zones.fw_passive
  depends_on         = [scaleway_instance_private_nic.fw_passive_ha]
}

resource "scaleway_ipam_ip" "fw_active_wan2" {
  count = length(var.wan_pn_keys) > 1 ? 1 : 0

  address    = var.fw_active_ips.wan2
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = var.wan_private_network_ids[var.wan_pn_keys[1]]
  }
  depends_on = [scaleway_ipam_ip.fw_active_ha]
}

resource "scaleway_instance_private_nic" "fw_active_wan2" {
  count = length(var.wan_pn_keys) > 1 ? 1 : 0

  private_network_id = var.wan_private_network_ids[var.wan_pn_keys[1]]
  server_id          = scaleway_instance_server.fw_active.id
  ipam_ip_ids        = [scaleway_ipam_ip.fw_active_wan2[0].id]
  zone               = local.zones.fw_active
  depends_on         = [scaleway_instance_private_nic.fw_active_ha]
}

# ---------------------------------------------------------------------------
# Destroy-time teardown helpers (fw_passive / fw_active).
#
# Standalone private-NIC resources cannot be reliably deleted by the provider
# while the server runs, the v2 API rejects the delete with "Can't delete a
# private network interface attached to a server" on production
# gateway-managed networks, and each NIC necessarily depends on the server
# for `server_id`, so Terraform would attempt the NIC deletes before the
# servers and fail. Each helper below depends on every NIC / IPAM reservation
# and its server, so Terraform destroys them FIRST; their `when = destroy`
# provisioners remove all of the server's private NICs via the CLI (v1 API,
# which accepts the delete on running servers), after which the NIC / IPAM /
# server resources delete cleanly, the provider tolerates 404 on pnics that
# are already gone. Idempotent: the loops are no-ops when there is nothing to
# delete. Makes `terraform destroy` (and `-replace`) a single command, no
# manual CLI + `state rm` dance.
# ---------------------------------------------------------------------------
resource "null_resource" "fw_passive_teardown" {
  depends_on = [
    scaleway_instance_server.fw_passive,
    scaleway_instance_private_nic.fw_passive_lan,
    scaleway_instance_private_nic.fw_passive_ha,
    # Whole-resource references: safe when count = 0, ordered after when present.
    scaleway_instance_private_nic.fw_passive_wan,
    scaleway_instance_private_nic.fw_passive_ha2,
    scaleway_instance_private_nic.fw_passive_mgmt,
    scaleway_instance_private_nic.fw_passive_wan2,
    scaleway_ipam_ip.fw_passive_lan,
    scaleway_ipam_ip.fw_passive_ha,
    scaleway_ipam_ip.fw_passive_wan,
    scaleway_ipam_ip.fw_passive_ha2,
    scaleway_ipam_ip.fw_passive_mgmt,
    scaleway_ipam_ip.fw_passive_wan2,
  ]

  triggers = {
    server_uuid     = split("/", scaleway_instance_server.fw_passive.id)[1]
    zone            = local.zones.fw_passive
    organization_id = var.organization_id
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

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = self.triggers.organization_id
    }
  }
}

resource "null_resource" "fw_active_teardown" {
  depends_on = [
    scaleway_instance_server.fw_active,
    scaleway_instance_private_nic.fw_active_lan,
    scaleway_instance_private_nic.fw_active_ha,
    # Whole-resource references: safe when count = 0, ordered after when present.
    scaleway_instance_private_nic.fw_active_wan,
    scaleway_instance_private_nic.fw_active_ha2,
    scaleway_instance_private_nic.fw_active_mgmt,
    scaleway_instance_private_nic.fw_active_wan2,
    scaleway_ipam_ip.fw_active_lan,
    scaleway_ipam_ip.fw_active_ha,
    scaleway_ipam_ip.fw_active_wan,
    scaleway_ipam_ip.fw_active_ha2,
    scaleway_ipam_ip.fw_active_mgmt,
    scaleway_ipam_ip.fw_active_wan2,
  ]

  triggers = {
    server_uuid     = split("/", scaleway_instance_server.fw_active.id)[1]
    zone            = local.zones.fw_active
    organization_id = var.organization_id
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

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = self.triggers.organization_id
    }
  }
}

# ---------------------------------------------------------------------------
# Config apply / reboot (CARP vendors only)
#
# OPNsense imports user_data["opnsense_config"] on first boot. A reboot is
# triggered whenever the rendered XML changes (or on the first deploy) to make
# sure the full CARP/pfsync stack is active. Same pattern as the blueprint
# firewall-ha module.
# ---------------------------------------------------------------------------
resource "null_resource" "fw_passive_apply_config" {
  count = local.is_carp ? 1 : 0

  triggers = {
    config_hash = sha256(local.fw_passive_xml)
    server_uuid = split("/", scaleway_instance_server.fw_passive.id)[1]
    zone        = local.zones.fw_passive
  }

  provisioner "local-exec" {
    command = "scw instance server reboot ${self.triggers.server_uuid} zone=${self.triggers.zone} --wait"

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = var.organization_id
    }
  }

  depends_on = [
    scaleway_instance_server.fw_passive,
    scaleway_instance_private_nic.fw_passive_ha,
    # Whole-resource reference: safe when wan is absent (count=0 in
    # flexible-IP mode), and when present (WAN-PN mode) it is attached after
    # the HA NIC, so the reboot always runs after all NICs are up.
    scaleway_instance_private_nic.fw_passive_wan,
  ]
}

resource "null_resource" "fw_active_apply_config" {
  count = local.is_carp ? 1 : 0

  triggers = {
    config_hash = sha256(local.fw_active_xml)
    server_uuid = split("/", scaleway_instance_server.fw_active.id)[1]
    zone        = local.zones.fw_active
  }

  provisioner "local-exec" {
    command = "scw instance server reboot ${self.triggers.server_uuid} zone=${self.triggers.zone} --wait"

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = var.organization_id
    }
  }

  depends_on = [
    scaleway_instance_server.fw_active,
    # Serialized: the standby (fw_passive) fully reboots with its new config before
    # the master (fw_active) does, so the pair never reboots simultaneously.
    null_resource.fw_passive_apply_config,
    scaleway_instance_private_nic.fw_active_ha,
    # Whole-resource reference: safe when wan is absent (count=0 in
    # flexible-IP mode), and when present (WAN-PN mode) it is attached after
    # the HA NIC, so the reboot always runs after all NICs are up.
    scaleway_instance_private_nic.fw_active_wan,
  ]
}

# ---------------------------------------------------------------------------
# Default routes (optional)
# ---------------------------------------------------------------------------
resource "scaleway_vpc_route" "wan_default_to_fw" {
  # Only meaningful with a WAN private network (not in flexible-IP mode).
  count = var.create_default_routes && local.wan_enabled ? 1 : 0

  vpc_id                     = var.wan_vpc_id
  description                = "Default route to firewall via WAN"
  tags                       = concat(var.tags, ["terraform", var.vendor])
  destination                = "0.0.0.0/0"
  nexthop_private_network_id = local.wan_primary_pn_id
  # CARP VIP IPAM ID when a WAN VIP is configured, else the fw_passive WAN NIC.
  nexthop_resource_id = try(scaleway_ipam_ip.vip_wan[0].id, scaleway_instance_private_nic.fw_passive_wan[0].id)
}

resource "scaleway_vpc_route" "lan_default_to_fw" {
  count = var.create_default_routes ? 1 : 0

  vpc_id                     = var.lan_vpc_id
  description                = "Default route to firewall via LAN"
  tags                       = concat(var.tags, ["terraform", var.vendor])
  destination                = "0.0.0.0/0"
  nexthop_private_network_id = local.lan_pn_id
  nexthop_resource_id        = local.is_carp && var.enable_vips ? scaleway_ipam_ip.vip_lan[0].id : scaleway_instance_private_nic.fw_passive_lan.id
}

# ---------------------------------------------------------------------------
# Optional test instances (LAN / WAN ping servers, low-cost validation)
# ---------------------------------------------------------------------------
resource "scaleway_instance_server" "lan_ping" {
  count = var.create_test_instances ? 1 : 0

  type       = "POP2-2C-8G"
  image      = "ubuntu-noble"
  name       = "${local.name_prefix}-${var.vendor}-lan-ping"
  zone       = local.zones.fw_passive
  project_id = var.project_id
  tags       = concat(var.tags, [var.vendor, "test"])
  root_volume {
    size_in_gb  = 10
    volume_type = "sbs_volume"
  }
}

resource "scaleway_instance_private_nic" "lan_ping" {
  count = var.create_test_instances ? 1 : 0

  private_network_id = local.lan_pn_id
  server_id          = scaleway_instance_server.lan_ping[0].id
  ipam_ip_ids        = [scaleway_ipam_ip.lan_ping_ip[0].id]
  zone               = local.zones.fw_passive
}

resource "scaleway_ipam_ip" "lan_ping_ip" {
  count = var.create_test_instances ? 1 : 0

  address    = cidrhost(var.lan_cidr, 5)
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.lan_pn_id
  }
}

resource "scaleway_instance_server" "wan_ping" {
  count = var.create_test_instances ? 1 : 0

  type       = "POP2-2C-8G"
  image      = "ubuntu-noble"
  name       = "${local.name_prefix}-${var.vendor}-wan-ping"
  zone       = local.zones.fw_passive
  project_id = var.project_id
  tags       = concat(var.tags, [var.vendor, "test"])
  root_volume {
    size_in_gb  = 10
    volume_type = "sbs_volume"
  }
}

resource "scaleway_ipam_ip" "wan_ping_ip" {
  count = var.create_test_instances ? 1 : 0

  address    = cidrhost(var.wan_cidr, 2)
  is_ipv6    = false
  project_id = var.project_id
  source {
    private_network_id = local.wan_primary_pn_id
  }
}

resource "scaleway_instance_private_nic" "wan_ping" {
  count = var.create_test_instances ? 1 : 0

  private_network_id = local.wan_primary_pn_id
  server_id          = scaleway_instance_server.wan_ping[0].id
  ipam_ip_ids        = [scaleway_ipam_ip.wan_ping_ip[0].id]
  zone               = local.zones.fw_passive
}

# Destroy-time teardown helpers for the optional test instances (same pattern
# as fw_passive_teardown / fw_active_teardown above). Gated on create_test_instances.
resource "null_resource" "lan_ping_teardown" {
  count = var.create_test_instances ? 1 : 0

  depends_on = [
    scaleway_instance_server.lan_ping,
    scaleway_instance_private_nic.lan_ping,
    scaleway_ipam_ip.lan_ping_ip,
  ]

  triggers = {
    server_uuid     = split("/", scaleway_instance_server.lan_ping[0].id)[1]
    zone            = local.zones.fw_passive
    organization_id = var.organization_id
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

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = self.triggers.organization_id
    }
  }
}

resource "null_resource" "wan_ping_teardown" {
  count = var.create_test_instances ? 1 : 0

  depends_on = [
    scaleway_instance_server.wan_ping,
    scaleway_instance_private_nic.wan_ping,
    scaleway_ipam_ip.wan_ping_ip,
  ]

  triggers = {
    server_uuid     = split("/", scaleway_instance_server.wan_ping[0].id)[1]
    zone            = local.zones.fw_passive
    organization_id = var.organization_id
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

    environment = {
      SCW_DEFAULT_ORGANIZATION_ID = self.triggers.organization_id
    }
  }
}
