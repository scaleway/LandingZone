# ---------------------------------------------------------------------------
# Stage 3 - Security Appliances: Outputs
# Blueprint-style outputs (access / test_protocol / resource_ids / ingress_rules)
# Adapted to the PGW topology: public gateways carry the public IPs (hub
# inbound door + egress PGW); the firewalls are private-only and managed
# exclusively through the hub door.
# ---------------------------------------------------------------------------

locals {
  fw_passive_uuid = split("/", module.firewall_ha.fw_passive_instance_id)[1]
  fw_active_uuid  = split("/", module.firewall_ha.fw_active_instance_id)[1]

  # Null-safe fallbacks: when create_test_instances=false the module map is
  # empty and every lookup below degrades to "" (never null, so string
  # interpolation cannot crash).
  hub_test_priv = try(module.test_instances["hub-test"].private_ips_map["pn"], "")
  spoke1_ip     = try(module.test_instances["spoke-1-test"].public_ips[0].address, "")
  spoke2_ip     = try(module.test_instances["spoke-2-test"].public_ips[0].address, "")
  spoke1_priv   = try(module.test_instances["spoke-1-test"].private_ips_map["pn"], "")
  spoke2_priv   = try(module.test_instances["spoke-2-test"].private_ips_map["pn"], "")

  fw_ssh_key  = "scw-lz/keys-${var.environment}/admin_key"
  vm_ssh_user = "ubuntu"

  # hub-test is internal-only (no flexible IP): reach it via
  # the hub door through the CARP MASTER (fw-active, :8023) to its LAN private IP.
  # All three SSH helpers are gated on create_test_instances so the outputs
  # stay valid (empty) when the test instances are switched off.
  hub_ssh     = local.factory.create_test_instances ? "ssh -i ${local.fw_ssh_key} -o ProxyCommand='ssh -i ${local.fw_ssh_key} -p 8023 -W %h:%p root@${local.door_ip}' ${local.vm_ssh_user}@${local.hub_test_priv}" : ""
  spoke_a_ssh = local.factory.create_test_instances ? "ssh -i ${local.fw_ssh_key} ${local.vm_ssh_user}@${local.spoke1_ip}" : ""
  spoke_b_ssh = local.factory.create_test_instances ? "ssh -i ${local.fw_ssh_key} ${local.vm_ssh_user}@${local.spoke2_ip}" : ""

  # The firewalls are private-only - SSH is exclusively through the hub
  # inbound door (hub PGW PAT: 8022 -> fw-passive, 8023 -> fw-active).
  # Dual door: active hub PGW (fr-par-2) + passive (fr-par-1), same PAT set on
  # both public IPs (see main.tf door_pat_rules). Active/passive: use door_ip
  # normally, switch to door_ip_passive if the active dies ("" when not
  # provisioned).
  door_ip         = scaleway_vpc_public_gateway_ip.hub.address
  door_ip_passive = length(scaleway_vpc_public_gateway_ip.hub_passive) > 0 ? scaleway_vpc_public_gateway_ip.hub_passive[0].address : ""
  fw_passive_ssh  = "ssh -i ${local.fw_ssh_key} root@${local.door_ip} -p 8022"
  fw_active_ssh   = "ssh -i ${local.fw_ssh_key} root@${local.door_ip} -p 8023"
}

output "access" {
  description = "Main access paths for Stage 3 (PGW topology - firewalls private-only)."
  value = {
    region = var.region
    zones = {
      fw_passive = local.factory.zones["fw-passive"]
      fw_active  = local.factory.zones["fw-active"]
    }
    firewall = {
      # Private-only: management is ONLY through the hub door.
      fw_passive_ssh   = local.fw_passive_ssh
      fw_active_ssh    = local.fw_active_ssh
      webui_fw_passive = "https://${local.door_ip}:8444"
      webui_fw_active  = "https://${local.door_ip}:8445"
    }
    hub_pgw_door = {
      public_ip         = local.door_ip
      public_ip_passive = local.door_ip_passive # failover door (fr-par-1); "" if not provisioned
      webui_vip         = "https://${local.door_ip}:8443"
      webui_fw_passive  = "https://${local.door_ip}:8444"
      webui_fw_active   = "https://${local.door_ip}:8445"
      ssh_fw_passive    = local.fw_passive_ssh
      ssh_fw_active     = local.fw_active_ssh
    }
    test_instances = {
      hub_test = local.hub_ssh != "" ? local.hub_ssh : "n/a - create_test_instances=false"
      spoke_1  = local.spoke_a_ssh != "" ? local.spoke_a_ssh : "n/a - create_test_instances=false"
      spoke_2  = local.spoke_b_ssh != "" ? local.spoke_b_ssh : "n/a - create_test_instances=false"
    }
    serial = {
      fw_passive = "scw instance server console ${local.fw_passive_uuid} zone=${local.factory.zones["fw-passive"]}"
      fw_active  = "scw instance server console ${local.fw_active_uuid} zone=${local.factory.zones["fw-active"]}"
    }
  }
}

output "test_protocol" {
  description = "Manual validation commands."
  value = {
    east_west = {
      allow = local.factory.create_test_instances ? "${local.spoke_a_ssh} 'ping -c3 ${local.spoke2_priv}; traceroute ${local.spoke2_priv}'" : "n/a - create_test_instances=false"
      # East-west is direct via the hub in BOTH directions - the asymmetric
      # [EW] deny is no longer in the data path (spoke -> hub routes beat the
      # hub 0.0.0.0/0 -> FW route).
      direct = local.factory.create_test_instances ? "${local.spoke_b_ssh} 'ping -c3 ${local.spoke1_priv}'  # attendu: 0% loss (hub-direct)" : "n/a - create_test_instances=false"
    }
    egress = {
      public_ip = local.factory.create_test_instances ? "${local.spoke_a_ssh} 'curl -4 --fail --max-time 10 https://myip.wtf/text'  # attendu: ${scaleway_vpc_public_gateway_ip.egress.address} (egress PGW)" : "n/a - create_test_instances=false"
      trace     = local.factory.create_test_instances ? "${local.spoke_a_ssh} 'traceroute 1.1.1.1'" : "n/a - create_test_instances=false"
    }
    firewall = {
      rules  = "terraform output -json ingress_rules | jq"
      health = "${local.fw_passive_ssh} 'hostname; opnsense-version; ifconfig vtnet1; pfctl -sr | wc -l'  # via hub door"
      logs   = "${local.fw_passive_ssh} 'tail -F /var/log/filter/latest.log | grep --line-buffered -i block'  # via hub door"
      # FW-own egress goes through the egress gateway group (defaultgw4
      # EGRESS_GROUP) - the hub PGW cannot forward internet bound traffic (hub
      # VPC 0/0->FW steering).
      # Verify on the MASTER (fw-active): a CARP standby cannot originate
      # VIP-sourced own traffic (OPNsense HA limitation - it is sent to the
      # master and dropped).
      fw_own_egress = "${local.fw_active_ssh} 'curl -4 --max-time 10 https://myip.wtf/text; netstat -rn | grep default'  # attendu: ${scaleway_vpc_public_gateway_ip.egress.address} (egress PGW masquerade)"
    }
    ha = {
      stop_fw_passive  = "scw instance server stop ${local.fw_passive_uuid} zone=${local.factory.zones["fw-passive"]} --wait"
      start_fw_passive = "scw instance server start ${local.fw_passive_uuid} zone=${local.factory.zones["fw-passive"]} --wait"
      stop_fw_active   = "scw instance server stop ${local.fw_active_uuid} zone=${local.factory.zones["fw-active"]} --wait"
      start_fw_active  = "scw instance server start ${local.fw_active_uuid} zone=${local.factory.zones["fw-active"]} --wait"
      webui            = "https://${local.door_ip}:8443" # CARP VIP via the hub door
    }
  }
}

output "resource_ids" {
  description = "Identifiers useful for manual operations."
  value = {
    fw_passive           = module.firewall_ha.fw_passive_instance_id
    fw_active            = module.firewall_ha.fw_active_instance_id
    fw_passive_zone      = local.factory.zones["fw-passive"]
    fw_active_zone       = local.factory.zones["fw-active"]
    hub_door_ip          = local.door_ip
    hub_door_ip_passive  = local.door_ip_passive
    egress_gw_ip         = scaleway_vpc_public_gateway_ip.egress.address
    egress_gw_ip_passive = length(scaleway_vpc_public_gateway_ip.egress_passive) > 0 ? scaleway_vpc_public_gateway_ip.egress_passive[0].address : null
    test_instances       = local.factory.create_test_instances ? { for k, v in module.test_instances : k => v.id } : {}
  }
}

# ---------------------------------------------------------------------------
# Firewall test battery config - the single machine-readable source for
# scripts/gen_fw_battery_env.sh (make fw-test-env), which regenerates
# scw-lz/envs/<env>/test-firewalls.env consumed by test-firewalls.sh.
# Everything the battery needs is derived here (live resource IDs + public
# IPs from this stage, design constants from the factory yaml) so the battery
# never runs against hand-maintained/stale values.
# ---------------------------------------------------------------------------
output "firewall_test_config" {
  description = "Live values for the firewall test battery (test-firewalls.sh). Consumed by scripts/gen_fw_battery_env.sh to regenerate scw-lz/envs/<env>/test-firewalls.env - no hand-maintained IPs/UUIDs/keys."
  value = {
    DOOR               = local.door_ip
    DOOR_PASSIVE       = local.door_ip_passive
    EGRESS             = scaleway_vpc_public_gateway_ip.egress.address
    EGRESS_PASSIVE     = length(scaleway_vpc_public_gateway_ip.egress_passive) > 0 ? scaleway_vpc_public_gateway_ip.egress_passive[0].address : ""
    SPOKE1_IP          = local.spoke1_ip
    SPOKE2_IP          = local.spoke2_ip
    SPOKE1_PRIV        = local.spoke1_priv
    SPOKE2_PRIV        = local.spoke2_priv
    HUBTEST_PRIV       = local.hub_test_priv
    MGMT_CIDRS         = join(" ", try(local.factory.management_cidrs, []))
    FW_PASSIVE_UUID    = local.fw_passive_uuid
    FW_ACTIVE_UUID     = local.fw_active_uuid
    FW_PASSIVE_ZONE    = local.factory.zones["fw-passive"]
    FW_ACTIVE_ZONE     = local.factory.zones["fw-active"]
    LAN_VIP            = local.factory.ipam.lan.vip
    EGRESS_VIP         = local.factory.ipam.egress.vip
    EGRESS_PGW         = local.factory.ipam.egress["pgw-active"]
    EGRESS_PGW_PASSIVE = try(local.factory.ipam.egress["pgw-passive"], "")
    HUB_PGW            = local.factory.ipam.lan["pgw-active"]
    HUB_PGW_PASSIVE    = try(local.factory.ipam.lan["pgw-passive"], "")
  }
}

output "ingress_rules" {
  description = "Hub steering into the FW (hub 0.0.0.0/0 -> FW CARP LAN VIP route - the ingress-rule redirect proved lossy 33-90% and was replaced)."
  value = {
    route_id                = scaleway_vpc_route.hub_default_to_fw.id
    nexthop_private_network = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
    nexthop_resource_ip     = module.firewall_ha.vip_lan_ip
  }
}

# --- Firewall image pipeline outputs (informational) ------------------------
output "firewall_1_image_object_key" {
  description = "Object key of the uploaded QCOW2 in the bucket (passive zone image)."
  value       = try(module.firewall_image_1[0].object_key, null)
}

output "firewall_2_image_object_key" {
  description = "Object key of the uploaded QCOW2 in the bucket (active zone image)."
  value       = try(module.firewall_image_2[0].object_key, null)
}

output "fw_volume_map" {
  description = "Map of zone -> SBS volume used as the OPNsense root volumes."
  value       = local.fw_volume_map
}

output "firewall_mgmt_sg_id" {
  description = "ID of the firewall-management security group (null if not created)."
  value       = length(scaleway_instance_security_group.firewall_mgmt) > 0 ? scaleway_instance_security_group.firewall_mgmt[0].id : null
}

output "fw_passive_lan_ip" {
  description = "LAN private IP of the passive firewall (ipam.lan.fw-passive) - consumed by the stage-5 FW exporter (fw_export_hosts)."
  value       = local.fw_passive_lan_ip
}

output "fw_active_lan_ip" {
  description = "LAN private IP of the active firewall (ipam.lan.fw-active) - consumed by the stage-5 FW exporter (fw_export_hosts)."
  value       = local.fw_active_lan_ip
}

output "golden_snapshot_ids" {
  description = "Map of firewall zone -> golden SBS snapshot ID (passive/active), produced in-project by the firewall_image modules from the operator-uploaded golden qcow2. Consumed by the fw-restore drill to clone the golden snapshots without a fragile name lookup."
  value = merge(
    module.firewall_image_1[0].snapshot_ids_full,
    module.firewall_image_2[0].snapshot_ids_full,
  )
}

# ---------------------------------------------------------------------------
# Rendered per-node OPNsense configs - consumed by the automated config-delivery
# script (scripts/fw-config-deliver.sh): it exports these to disk, ships them to
# hub-test over the hub PN, applies them on each FW via console, and reboots.
# ---------------------------------------------------------------------------
output "fw_passive_config_xml" {
  description = "Rendered OPNsense config for the passive firewall (private-only)."
  value       = local.fw_passive_config_xml
  sensitive   = true
}

output "fw_active_config_xml" {
  description = "Rendered OPNsense config for the active firewall (private-only)."
  value       = local.fw_active_config_xml
  sensitive   = true
}
