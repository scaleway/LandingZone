# ---------------------------------------------------------------------------
# Config mapping, vendor-specific config backups bundled with the module.
#
# Supported vendor is opnsense (CARP): it injects per-node XML via
# user_data["opnsense_config"] (base64, imported on first boot), or the
# bundled hub-spoke template (templates/vpc-hub-spoke-fw.xml) rendered with
# hostname/LAN IP/SSH key.
#
# Other vendors (fortigate/paloalto/stormshield) are planned add-ons (tracked
# as GitHub issues) and are not wired in this module.
# ---------------------------------------------------------------------------

locals {
  _hostname_fw = "fw"

  # Bundled defaults, used when the caller doesn't set config_paths.
  default_config_paths = {
    opnsense_fw_passive = "${path.module}/config/opnsense/fw_passive.xml"
    opnsense_fw_active  = "${path.module}/config/opnsense/fw_active.xml"
  }

  config_paths = var.config_paths != null ? var.config_paths : local.default_config_paths
}

locals {
  _fw_template = "${path.module}/config/opnsense/templates/vpc-hub-spoke-fw.xml"

  # Caller-supplied per-node XML; try() so a missing file doesn't break plan.
  _opnsense_fw_passive_path = try(var.config_paths.opnsense_fw_passive, null)
  _opnsense_fw_active_path  = try(var.config_paths.opnsense_fw_active, null)

  is_opnsense = var.vendor == "opnsense"

  # Fallback: bundled hub-spoke template rendered per node.
  derived_fw_passive_xml = templatefile(local._fw_template, {
    hostname     = "${local._hostname_fw}-passive"
    lan_ip       = var.fw_passive_ips.lan
    admin_pubkey = var.admin_pubkey
  })
  derived_fw_active_xml = templatefile(local._fw_template, {
    hostname     = "${local._hostname_fw}-active"
    lan_ip       = var.fw_active_ips.lan
    admin_pubkey = var.admin_pubkey
  })

  # Config XML precedence (CARP vendors only):
  #   1. caller-rendered content (fw*_config_xml, no plan-time file()),
  #   2. caller file path (try(file()), apply-only files don't break plan),
  #   3. bundled template (fallback).
  fw_passive_xml = local.is_opnsense ? (
    var.fw_passive_config_xml != null ? var.fw_passive_config_xml : (
      local._opnsense_fw_passive_path != null ? try(file(local._opnsense_fw_passive_path), local.derived_fw_passive_xml) : local.derived_fw_passive_xml
    )
  ) : local.derived_fw_passive_xml
  fw_active_xml = local.is_opnsense ? (
    var.fw_active_config_xml != null ? var.fw_active_config_xml : (
      local._opnsense_fw_active_path != null ? try(file(local._opnsense_fw_active_path), local.derived_fw_active_xml) : local.derived_fw_active_xml
    )
  ) : local.derived_fw_active_xml
}
