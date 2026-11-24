terraform {
  required_version = ">= 1.0"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  # Use S3-compatible backend for remote state (created by scw-lz/bootstrap)
  # Initialize with: terraform init -reconfigure -backend-config=../../envs/<env>/backend-<env>.tfvars
  backend "s3" {
    key = "stage-3/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Locals, root handles + fixed IP plan. Hub/spokes come from Stage 2; this
# stage owns sync + the HA pair + the inbound hub door.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Common tags: the org's tag policy (var.common_tags) plus the toolkit-
# reserved markers managed-by / env / stage. Composition is the single
# source of truth in modules/tags; local.common_tags / common_tags_map below
# just alias the module outputs so the rest of this file keeps using
# local.common_tags.
# ---------------------------------------------------------------------------
module "common_tags" {
  source      = "../../../modules/tags"
  user_tags   = var.common_tags
  environment = local.environment
  stage_id    = "stage3"
}

locals {
  common_tags     = module.common_tags.list
  common_tags_map = module.common_tags.map

  # YAML factory (same pattern as stages 0/1/2/4): per-env design data from
  # envs/<env>/data/security-appliances-<env>.yaml (-demo preferred). Secrets
  # stay in gitignored tfvars, never committed.
  factory_file = fileexists("${path.module}/../../envs/${local.environment}/data/security-appliances-${local.environment}-demo.yaml") ? "${path.module}/../../envs/${local.environment}/data/security-appliances-${local.environment}-demo.yaml" : "${path.module}/../../envs/${local.environment}/data/security-appliances-${local.environment}.yaml"

  factory = yamldecode(file(local.factory_file))

  # Non-secret image keys from the YAML + upload creds (upload itself is done
  # by the upload-wait gate; these default "" for module-signature compat).
  fw_image_1 = merge(local.factory.firewall_image_1, {
    upload_access_key = var.upload_access_key
    upload_secret_key = var.upload_secret_key
  })
  fw_image_2 = merge(local.factory.firewall_image_2, {
    upload_access_key = var.upload_access_key
    upload_secret_key = var.upload_secret_key
  })

  # Normalize the untyped YAML map into typed values for for_each/lookup().
  # lan_ip pins each VM's static PN address (same source as the FW egress
  # rule, so the two can't drift); try() => DHCP when a pin is absent.
  test_instances = {
    for k, v in local.factory.test_instances : k => {
      name                = v.name
      vpc_key             = v.vpc_key
      private_network_key = v.private_network_key
      instance_type       = try(v.instance_type, "DEV1-S")
      image               = try(v.image, "ubuntu_jammy")
      security_group_key  = try(v.security_group_key, "internal-sg")
      zone                = try(v.zone, null)
      enable_dynamic_ip   = try(v.enable_dynamic_ip, false)
      ips                 = try(v.ips, {})
      tags                = try(v.tags, ["test"])
      user_data           = try(v.user_data, {})
      lan_ip = try(v.lan_ip,
        k == "hub-test" ? local.factory.ipam.lan.hub_test :
        k == "spoke-1-test" ? try(local.factory.ipam.spoke1.test, null) :
        k == "spoke-2-test" ? try(local.factory.ipam.spoke2.test, null) :
      null)
    }
  }

  project_id        = data.terraform_remote_state.bootstrap.outputs.project_ids[var.project_key]
  environment       = data.terraform_remote_state.bootstrap.outputs.environment
  name_prefix       = "lz-${local.environment}"
  bucket_suffix     = data.terraform_remote_state.bootstrap.outputs.bucket_suffix
  image_bucket_name = var.image_bucket_name != "" ? var.image_bucket_name : (local.factory.image_bucket_name != "" ? local.factory.image_bucket_name : "${var.state_bucket_prefix != null ? var.state_bucket_prefix : "lz"}-${local.environment}-image-import-${local.bucket_suffix}")

  # Object keys the upload-wait gate must wait for: each member may import a
  # different build, so never assume a single shared name. Deduplicated.
  upload_wait_keys = distinct(compact([
    local.fw_image_1 != null ? local.fw_image_1.object_key : null,
    local.fw_image_2 != null ? local.fw_image_2.object_key : null,
  ]))

  # S3 endpoint of the image bucket (any configured image carries it).
  image_s3_endpoint = (
    local.fw_image_1 != null ? local.fw_image_1.s3_endpoint :
    local.fw_image_2 != null ? local.fw_image_2.s3_endpoint :
    "https://s3.${var.region}.scw.cloud"
  )

  # Auto-push map for the upload-wait gate: bundled file (no 2.2 GB
  # re-download) > source_url (gate curls + uploads) > "" = manual "UPLOAD
  # REQUIRED". `...` groups the HA pair's shared object_key into a list.
  bundled_uploads = {
    for img in [local.fw_image_1, local.fw_image_2] :
    img.object_key => (
      fileexists("${path.module}/providers/${img.vendor}/${img.object_key}")
      ? abspath("${path.module}/providers/${img.vendor}/${img.object_key}")
      : try(img.source_url, null) != null
      ? "url:${img.source_url}"
      : ""
    )...
    if img != null
  }

  # Collapse grouped duplicates to one non-empty path per key.
  bundled_paths = {
    for k, plist in local.bundled_uploads : k => try(compact(distinct(plist))[0], "")
  }

  # key=path lines for the gate's local-exec (bundled files only, so the
  # script auto-uploads just those).
  bundled_lines = join("\n", [
    for k, p in local.bundled_paths : p != "" ? "${k}=${p}" : ""
  ])

  # Stage 2 network handles (single source of truth)
  hub_vpc_id                 = data.terraform_remote_state.stage2.outputs.vpc_ids["hub"]
  spoke1_vpc_id              = data.terraform_remote_state.stage2.outputs.vpc_ids["spoke-1"]
  spoke2_vpc_id              = data.terraform_remote_state.stage2.outputs.vpc_ids["spoke-2"]
  hub_private_network_ids    = data.terraform_remote_state.stage2.outputs.private_network_ids["hub"]
  spoke1_private_network_ids = data.terraform_remote_state.stage2.outputs.private_network_ids["spoke-1"]
  spoke2_private_network_ids = data.terraform_remote_state.stage2.outputs.private_network_ids["spoke-2"]

  # Peering connectors looked up by name (+ vpc_id): stage-2's vpc_peering_*
  # outputs are empty (guarded on tfvars) even though the peerings live in the
  # factory YAML. Both directions share a name; vpc_id (spoke) picks the
  # spoke-side connector pointing at the hub.
  peering_spoke1_to_hub = data.scaleway_vpc_connector.spoke1_to_hub.id
  peering_spoke2_to_hub = data.scaleway_vpc_connector.spoke2_to_hub.id

  # IP plan (fixed, deterministic) from the per-env factory's ipam, single
  # source of truth.
  hub_cidr      = local.factory.hub_subnet_cidr           # 10.10.0.0/24 (Stage 2)
  spoke_a_cidr  = local.factory.spoke1_subnet_cidr        # 10.20.0.0/24 (Stage 2)
  spoke_b_cidr  = local.factory.spoke2_subnet_cidr        # 10.30.0.0/24 (Stage 2)
  hub_test_cidr = "${local.factory.ipam.lan.hub_test}/32" # hub-test agent (FW egress rule src)

  # LAN side (hub-net)
  fw_vip            = local.factory.ipam.lan.vip # CARP LAN VIP (ingress next-hop + SNAT)
  fw_passive_lan_ip = local.factory.ipam.lan["fw-passive"]
  fw_active_lan_ip  = local.factory.ipam.lan["fw-active"]

  carp_vhid        = local.factory.ipam.vhids.lan
  carp_vmac        = local.factory.ipam.vmacs.lan # 0x0a == vhid 10
  carp_vhid_egress = local.factory.ipam.vhids.egress
  carp_vmac_egress = local.factory.ipam.vmacs.egress # 0x0b == vhid 11
  carp_password    = var.carp_password

  # HA sync side (new VPC owned by Stage 3)
  sync_cidr          = local.factory.ha_sync_cidr # 10.255.0.0/24
  fw_passive_sync_ip = local.factory.ipam.sync["fw-passive"]
  fw_active_sync_ip  = local.factory.ipam.sync["fw-active"]

  # Hub PGW inbound door on hub-net; dual PGWs give cross-AZ redundancy, the
  # OPNsense side pins management reply routes to a group over [active, passive].
  hub_pgw_active_lan_ip  = local.factory.ipam.lan["pgw-active"]
  hub_pgw_passive_lan_ip = try(local.factory.ipam.lan["pgw-passive"], null)

  # Egress plane: dual PGWs remove the single-AZ dependency, if the tenants'
  # AZ dies, traffic fails over via the OPNsense gateway group. Public egress
  # IP changes on failover.
  egress_cidr               = local.factory.egress_cidr                           # 10.4.0.0/24
  egress_pgw_active_lan_ip  = local.factory.ipam.egress["pgw-active"]             # active (fr-par-2)
  egress_pgw_passive_lan_ip = try(local.factory.ipam.egress["pgw-passive"], null) # passive (fr-par-1)
  egress_vip                = local.factory.ipam.egress.vip                       # CARP egress VIP (SNAT + nexthop)
  fw_passive_wan_ip         = local.factory.ipam.egress["fw-passive"]
  fw_active_wan_ip          = local.factory.ipam.egress["fw-active"]

  # Alternate AZ (opposite var.zone, tenants' plane): passive PGWs land here.
  alt_zone = var.zone == "fr-par-1" ? "fr-par-2" : "fr-par-1"

  # Gateway lists for per-vendor config templates: active first, passive
  # optional. The one provider-neutral contract between this stage's PGWs
  # and the vendor configs.
  egress_gateways = compact([local.egress_pgw_active_lan_ip, local.egress_pgw_passive_lan_ip])
  hub_gateways    = compact([local.hub_pgw_active_lan_ip, local.hub_pgw_passive_lan_ip])

  # VPN client network (template placeholder; connectivity disabled by default)
  client_cidr = local.factory.ipam.vpn_client_cidr

  # Hub door PAT rules: canonical set below (webui 8443/8444/8445->443,
  # ssh 8022/8023->22) as static resources; the YAML only re-parameterizes
  # their ports/targets. Add/remove rules by editing the resource blocks.
  door_target_ip = {
    vip          = local.fw_vip
    "fw-passive" = local.fw_passive_lan_ip
    "fw-active"  = local.fw_active_lan_ip
  }
  door_pat_rules = merge(
    {
      webui_vip        = { target = "vip", private_port = 443, public_port = 8443, protocol = "tcp" }
      webui_fw_passive = { target = "fw-passive", private_port = 443, public_port = 8444, protocol = "tcp" }
      webui_fw_active  = { target = "fw-active", private_port = 443, public_port = 8445, protocol = "tcp" }
      ssh_fw_passive   = { target = "fw-passive", private_port = 22, public_port = 8022, protocol = "tcp" }
      ssh_fw_active    = { target = "fw-active", private_port = 22, public_port = 8023, protocol = "tcp" }
    },
    { for k, v in try(local.factory.door_pat_rules, {}) : k => merge(
      { target = "vip", private_port = null, public_port = null, protocol = "tcp" },
      v,
    ) }
  )

  # Firewall image volumes - from modules/firewall-image (SBS snapshots -> SBS
  # volumes), passed to modules/firewall as snapshot_ids { zone -> {volume} }
  fw_volume_map = {
    "${local.factory.zones["fw-passive"]}" = {
      volume_id = "${local.factory.zones["fw-passive"]}/${try(module.firewall_image_1[0].volume_ids[local.factory.zones["fw-passive"]].volume_id, "00000000-0000-0000-0000-000000000000")}"
      size_gb   = local.fw_image_1.snapshot_size
    }
    "${local.factory.zones["fw-active"]}" = {
      volume_id = "${local.factory.zones["fw-active"]}/${try(module.firewall_image_2[0].volume_ids[local.factory.zones["fw-active"]].volume_id, "00000000-0000-0000-0000-000000000000")}"
      size_gb   = local.fw_image_2.snapshot_size
    }
  }
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    # bootstrap's local state path (written into remote_state-<env>.tfvars).
    path = var.stage0_state_path
  }
}

data "terraform_remote_state" "stage1" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-1/terraform.tfstate"
    endpoints = {
      s3 = var.state_endpoint
    }
    access_key                  = var.state_access_key
    secret_key                  = var.state_secret_key
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

data "terraform_remote_state" "stage2" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-2/terraform.tfstate"
    endpoints = {
      s3 = var.state_endpoint
    }
    access_key                  = var.state_access_key
    secret_key                  = var.state_secret_key
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
  }
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = local.project_id
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# OPNsense config rendering: opnsense-config.xml.tftpl once per HA node,
# injected via user_data["opnsense_config"] (native import on first boot).
# WAN = egress plane; FW default + spoke route-to use the EGRESS gateway
# group. Details in the XML template.
# ---------------------------------------------------------------------------
locals {
  # SSH keys (single source of truth): admin key from bootstrap, backup
  # exporter key from scw-lz/keys-<env>/fw-backup/. Each overridable via a var.
  fw_admin_ssh_key = var.opnsense_ssh_public_key != "" ? var.opnsense_ssh_public_key : trimspace(data.terraform_remote_state.bootstrap.outputs.ssh_public_keys["admin_key"])
  fw_backup_ssh_key = var.opnsense_backup_ssh_public_key != "" ? var.opnsense_backup_ssh_public_key : (
    fileexists("${path.module}/../../keys-${var.environment}/fw-backup/id_ed25519.pub") ? trimspace(file("${path.module}/../../keys-${var.environment}/fw-backup/id_ed25519.pub")) : ""
  )

  # Common template variables (shared by fw-passive and fw-active)
  tpl_common = {
    fw_vip                        = local.fw_vip
    hub_cidr                      = local.hub_cidr
    hub_gateways                  = local.hub_gateways
    egress_vip                    = local.egress_vip
    egress_gateways               = local.egress_gateways
    spoke_a_cidr                  = local.spoke_a_cidr
    spoke_b_cidr                  = local.spoke_b_cidr
    hub_test_cidr                 = local.hub_test_cidr
    carp_vhid                     = local.carp_vhid
    carp_vhid_egress              = local.carp_vhid_egress
    carp_password                 = local.carp_password
    opnsense_root_password        = var.opnsense_root_password
    opnsense_root_password_hash   = var.opnsense_root_password_hash
    management_cidrs              = local.factory.management_cidrs
    enable_connectivity           = local.factory.enable_connectivity_spoke
    enable_spoke_asymmetric_rules = local.factory.enable_spoke_asymmetric_rules
    fw_passive_lan_ip             = local.fw_passive_lan_ip
    fw_active_lan_ip              = local.fw_active_lan_ip
    client_cidr                   = local.client_cidr
    authorizedkeys_b64            = base64encode("${local.fw_admin_ssh_key}\n${local.fw_backup_ssh_key}\n")
  }

  tpl_fw_passive = merge(local.tpl_common, {
    hostname   = "fw-passive-${local.factory.zones["fw-passive"]}"
    fw_lan_ip  = local.fw_passive_lan_ip  # backup node LAN IP (static)
    fw_wan_ip  = local.fw_passive_wan_ip  # egress PN
    fw_sync_ip = local.fw_passive_sync_ip # HA sync IP (static)
    # Private-only (no flexible public IP). fw-passive is STANDBY: the hub VPC
    # drops steered traffic to fr-par-1 targets, so the MASTER must share the
    # fr-par-2 zone with the tenant plane (fw-active, advskew 0).
    carp_advskew     = 100
    carp_peer        = local.fw_active_lan_ip
    carp_peer_egress = local.fw_active_wan_ip
    pfsync_peer      = local.fw_active_sync_ip
    xmlrpc_sync_to   = ""
  })

  tpl_fw_active = merge(local.tpl_common, {
    hostname   = "fw-active-${local.factory.zones["fw-active"]}"
    fw_lan_ip  = local.fw_active_lan_ip  # designated MASTER node LAN IP (static)
    fw_wan_ip  = local.fw_active_wan_ip  # egress PN
    fw_sync_ip = local.fw_active_sync_ip # HA sync IP (static)
    # Private-only. fw-active is the MASTER (best advskew): same zone as every
    # tenant/test/client and both PGWs, so CARP VIP delivery is same-zone.
    # fw-passive stays a hot cross-zone standby via CARP/pfsync.
    carp_advskew     = 0
    carp_peer        = local.fw_passive_lan_ip
    carp_peer_egress = local.fw_passive_wan_ip
    pfsync_peer      = local.fw_passive_sync_ip
    xmlrpc_sync_to   = local.fw_passive_lan_ip
  })

  fw_passive_config_xml = templatefile("${path.module}/providers/opnsense/opnsense-config.xml.tftpl", local.tpl_fw_passive)
  fw_active_config_xml  = templatefile("${path.module}/providers/opnsense/opnsense-config.xml.tftpl", local.tpl_fw_active)
}

# ---------------------------------------------------------------------------
# Existing Stage-2 spoke->hub peering connectors (looked up by name)
# ---------------------------------------------------------------------------
data "scaleway_vpc_connector" "spoke1_to_hub" {
  name   = "${local.name_prefix}-peering-hub-to-spoke-1"
  vpc_id = local.spoke1_vpc_id
}

data "scaleway_vpc_connector" "spoke2_to_hub" {
  name   = "${local.name_prefix}-peering-hub-to-spoke-2"
  vpc_id = local.spoke2_vpc_id
}

# ---------------------------------------------------------------------------
# Synchronisation VPC (pfsync + XMLRPC, cross-zone) - owned by Stage 3
# ---------------------------------------------------------------------------
module "vpc_sync" {
  source = "../../../modules/vpc"

  name       = "${local.name_prefix}-sync"
  project_id = local.project_id
  region     = var.region
  tags       = concat(local.common_tags, ["ha", "sync"])

  enable_routing                   = true
  enable_custom_routes_propagation = true
  enable_transitivity              = false

  private_networks = {
    sync = {
      name             = "${local.name_prefix}-pn-sync"
      ipv4_subnet_cidr = local.sync_cidr
    }
  }
}

# ---------------------------------------------------------------------------
# HA OPNsense CARP pair (modules/firewall). LAN = hub PN (stage 2),
# HA = sync VPC (pfsync + XMLRPC), WAN = egress PN (private-only).
# ---------------------------------------------------------------------------
# Provider guard (see PROVIDERS.md): only 'opnsense' is wired end-to-end today.
resource "null_resource" "provider_wired_guard" {
  lifecycle {
    precondition {
      condition     = local.factory.firewall_provider == "opnsense"
      error_message = "firewall_provider '${local.factory.firewall_provider}' is not wired end-to-end yet - only 'opnsense' is deployed today. See PROVIDERS.md for the add-on roadmap."
    }
  }
}

module "firewall_ha" {
  source = "../../../modules/firewall"

  vendor          = local.factory.firewall_provider
  project_id      = local.project_id
  region          = var.region
  environment     = local.environment
  tags            = local.common_tags
  organization_id = var.organization_id

  zones = {
    fw_passive = local.factory.zones["fw-passive"]
    fw_active  = local.factory.zones["fw-active"]
  }

  snapshot_ids  = local.fw_volume_map
  instance_type = local.factory.fw_instance_type

  # LAN  = hub VPC private network (Stage 2)
  lan_vpc_id              = local.hub_vpc_id
  lan_private_network_ids = local.hub_private_network_ids
  lan_pn_key              = local.factory.hub_lan_pn_key
  lan_cidr                = local.factory.hub_subnet_cidr

  # HA   = sync VPC (this stage) - pfsync + XMLRPC
  ha_vpc_id              = module.vpc_sync.id
  ha_private_network_ids = module.vpc_sync.private_network_ids
  ha_pn_key              = "sync"

  # WAN = egress plane: opt2 NIC (vtnet3) on the egress PN, private-only.
  wan_vpc_id              = module.vpc_egress.id
  wan_private_network_ids = module.vpc_egress.private_network_ids
  wan_pn_keys             = ["egress"]
  wan_cidr                = local.factory.egress_cidr

  # Instance SGs are zone-scoped - one SG per node zone (fw_passive @ fr-par-1,
  # fw_active @ fr-par-2). The module falls back to "firewall_mgmt" if a node
  # key is absent.
  security_group_ids = {
    fw_passive = local.factory.create_firewall_mgmt_sg ? scaleway_instance_security_group.firewall_mgmt_az1[0].id : null
    fw_active  = local.factory.create_firewall_mgmt_sg ? scaleway_instance_security_group.firewall_mgmt[0].id : null
  }

  # Private-only: no fw_passive_ip_id / fw_active_ip_id (module default null);
  # FW-own default is HUB_PGW (config template).
  fw_passive_ips = {
    wan = local.fw_passive_wan_ip # egress PN
    lan = local.fw_passive_lan_ip
    ha  = local.fw_passive_sync_ip
  }
  fw_active_ips = {
    wan = local.fw_active_wan_ip # egress PN
    lan = local.fw_active_lan_ip
    ha  = local.fw_active_sync_ip
  }

  # CARP VIPs - LAN (hub) + egress. Same vhid -> same VMAC.
  vip_ips = {
    lan = local.fw_vip
    wan = local.egress_vip
  }
  vip_lan_mac = local.carp_vmac
  vip_wan_mac = local.carp_vmac_egress

  enable_vips           = true
  create_default_routes = local.factory.create_default_routes
  create_test_instances = false

  # Rendered per-node XML (locals above), injected via user_data["opnsense_config"].
  fw_passive_config_xml = local.fw_passive_config_xml
  fw_active_config_xml  = local.fw_active_config_xml

  admin_pubkey = local.fw_admin_ssh_key

  name    = "${local.name_prefix}-ha-firewall"
  ha_cidr = local.sync_cidr
}

# NOTE: the inline egress plane below replaces the blueprint's modules/egress
# (kept commented as a reference).

# ---------------------------------------------------------------------------
# Egress VPC (WAN side), the firewalls' opt2 NIC lives here; the egress PGW
# below is the spokes' outbound NAT (stable public IP). The firewalls
# themselves are private-only, their own egress goes via HUB_PGW.
# ---------------------------------------------------------------------------
module "vpc_egress" {
  source = "../../../modules/vpc"

  name       = "${local.name_prefix}-egress"
  project_id = local.project_id
  region     = var.region
  tags       = concat(local.common_tags, ["egress"])

  enable_routing                   = true
  enable_custom_routes_propagation = true
  enable_transitivity              = false

  private_networks = {
    egress = {
      name             = "${local.name_prefix}-pn-egress"
      ipv4_subnet_cidr = local.egress_cidr
    }
  }
}

# --- Active egress Public Gateway (var.zone) ---------------------------------
# Dual egress: active here + passive below (alt zone); both masquerade the
# egress PN independently, OPNsense EGRESS_GROUP drives default + route-to.
resource "scaleway_ipam_ip" "egress_pgw" {
  address    = local.egress_pgw_active_lan_ip
  is_ipv6    = false
  project_id = local.project_id
  tags       = concat(local.common_tags, ["firewall", "pgw-egress"])

  source {
    private_network_id = module.vpc_egress.private_network_ids["egress"]
  }
}

resource "scaleway_vpc_public_gateway_ip" "egress" {
  zone = var.zone
}

resource "scaleway_vpc_public_gateway" "egress" {
  name       = "${local.name_prefix}-pgw-egress"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.egress.id
  project_id = local.project_id
  zone       = var.zone
  tags       = concat(local.common_tags, ["firewall", "pgw-egress"])
}

resource "scaleway_vpc_gateway_network" "egress" {
  gateway_id         = scaleway_vpc_public_gateway.egress.id
  private_network_id = module.vpc_egress.private_network_ids["egress"]
  enable_masquerade  = true
  # No default push: spoke egress is policy-routed (route-to EGRESS_PGW) and
  # FW default is HUB_PGW, a pushed 0.0.0.0/0 would compete with both.
  zone = var.zone

  ipam_config {
    push_default_route = false
    ipam_ip_id         = scaleway_ipam_ip.egress_pgw.id
  }
}

# --- Passive Egress Public Gateway (alt zone, cross-AZ) ----------------------
# Same egress PN; removes the single-AZ dependency (EGRESS group falls over
# here on AZ loss). Public egress IP changes on failover.
resource "scaleway_ipam_ip" "egress_pgw_passive" {
  count      = length(local.egress_gateways) > 1 ? 1 : 0
  address    = local.egress_gateways[1]
  is_ipv6    = false
  project_id = local.project_id
  tags       = concat(local.common_tags, ["firewall", "pgw-egress", "passive"])

  source {
    private_network_id = module.vpc_egress.private_network_ids["egress"]
  }
}

resource "scaleway_vpc_public_gateway_ip" "egress_passive" {
  count = length(local.egress_gateways) > 1 ? 1 : 0
  zone  = local.alt_zone
}

resource "scaleway_vpc_public_gateway" "egress_passive" {
  count      = length(local.egress_gateways) > 1 ? 1 : 0
  name       = "${local.name_prefix}-pgw-egress-passive"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.egress_passive[0].id
  project_id = local.project_id
  zone       = local.alt_zone
  tags       = concat(local.common_tags, ["firewall", "pgw-egress", "passive"])
}

resource "scaleway_vpc_gateway_network" "egress_passive" {
  count              = length(local.egress_gateways) > 1 ? 1 : 0
  gateway_id         = scaleway_vpc_public_gateway.egress_passive[0].id
  private_network_id = module.vpc_egress.private_network_ids["egress"]
  enable_masquerade  = true
  # No default push either, the FW owns the default/route-to path (see active).
  zone = local.alt_zone

  ipam_config {
    push_default_route = false
    ipam_ip_id         = scaleway_ipam_ip.egress_pgw_passive[0].id
  }
}

# ---------------------------------------------------------------------------
# Hub Public Gateway: the stable inbound door (management via PAT) on the
# existing hub PN. No default push (would break routed public IPs and compete
# with the 0.0.0.0/0 -> FW route). PAT is DNAT-only, so reply routes go back
# through the door via HUB_GROUP (active -> passive on failover).
# ---------------------------------------------------------------------------
resource "scaleway_ipam_ip" "hub_pgw" {
  address    = local.hub_pgw_active_lan_ip
  is_ipv6    = false
  project_id = local.project_id
  tags       = concat(local.common_tags, ["firewall", "pgw-hub"])

  source {
    private_network_id = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
  }
}

# Public IP of the hub gateway (the single stable inbound door).
resource "scaleway_vpc_public_gateway_ip" "hub" {
  zone = var.zone
}

resource "scaleway_vpc_public_gateway" "hub" {
  name       = "${local.name_prefix}-pgw-hub"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.hub.id
  project_id = local.project_id
  zone       = var.zone
  tags       = concat(local.common_tags, ["firewall", "pgw-hub"])
}

# Attach the gateway to the existing hub PN - inbound door only.
resource "scaleway_vpc_gateway_network" "hub" {
  gateway_id         = scaleway_vpc_public_gateway.hub.id
  private_network_id = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
  enable_masquerade  = true
  # No default push: hub already steers 0.0.0.0/0 -> FW; a platform default
  # would compete.
  zone = var.zone

  ipam_config {
    push_default_route = false
    ipam_ip_id         = scaleway_ipam_ip.hub_pgw.id
  }
}

# --- Passive Hub Public Gateway (alt zone, cross-AZ door) --------------------
# Same hub PN + same PAT rules; operators switch to this public IP on active
# loss. PAT is DNAT-only, so replies must leave via the door they entered,
# HUB_GROUP pins both halves to the active door.
resource "scaleway_ipam_ip" "hub_pgw_passive" {
  count      = length(local.hub_gateways) > 1 ? 1 : 0
  address    = local.hub_gateways[1]
  is_ipv6    = false
  project_id = local.project_id
  tags       = concat(local.common_tags, ["firewall", "pgw-hub", "passive"])

  source {
    private_network_id = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
  }
}

resource "scaleway_vpc_public_gateway_ip" "hub_passive" {
  count = length(local.hub_gateways) > 1 ? 1 : 0
  zone  = local.alt_zone
}

resource "scaleway_vpc_public_gateway" "hub_passive" {
  count      = length(local.hub_gateways) > 1 ? 1 : 0
  name       = "${local.name_prefix}-pgw-hub-passive"
  type       = "VPC-GW-S"
  ip_id      = scaleway_vpc_public_gateway_ip.hub_passive[0].id
  project_id = local.project_id
  zone       = local.alt_zone
  tags       = concat(local.common_tags, ["firewall", "pgw-hub", "passive"])
}

resource "scaleway_vpc_gateway_network" "hub_passive" {
  count              = length(local.hub_gateways) > 1 ? 1 : 0
  gateway_id         = scaleway_vpc_public_gateway.hub_passive[0].id
  private_network_id = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
  enable_masquerade  = true
  # Same as active: no default push (hub steers 0.0.0.0/0 -> FW).
  zone = local.alt_zone

  ipam_config {
    push_default_route = false
    ipam_ip_id         = scaleway_ipam_ip.hub_pgw_passive[0].id
  }
}

# PAT rules, one full set per door gateway (active + passive), same public
# ports from local.door_pat_rules (factory YAML, resolved via ipam).
locals {
  door_gateway_keys = compact(["active", length(local.hub_gateways) > 1 ? "passive" : ""])
  door_gateway_ids = {
    active  = scaleway_vpc_public_gateway.hub.id
    passive = length(local.hub_gateways) > 1 ? scaleway_vpc_public_gateway.hub_passive[0].id : ""
  }
  # PAT rules must live in the gateway's zone (active = var.zone, passive = alt).
  door_gateway_zones = {
    active  = var.zone
    passive = length(local.hub_gateways) > 1 ? local.alt_zone : ""
  }
}

resource "scaleway_vpc_public_gateway_pat_rule" "door" {
  for_each = {
    for combo in setproduct(local.door_gateway_keys, keys(local.door_pat_rules)) :
    "${combo[0]}:${combo[1]}" => { gw = combo[0], rule = combo[1] }
  }

  gateway_id   = local.door_gateway_ids[each.value.gw]
  zone         = local.door_gateway_zones[each.value.gw]
  private_ip   = local.door_target_ip[local.door_pat_rules[each.value.rule].target]
  private_port = local.door_pat_rules[each.value.rule].private_port
  public_port  = local.door_pat_rules[each.value.rule].public_port
  protocol     = local.door_pat_rules[each.value.rule].protocol
  depends_on   = [scaleway_vpc_gateway_network.hub, scaleway_vpc_gateway_network.hub_passive]
}

# ---------------------------------------------------------------------------
# Egress <-> Hub VPC connectors (disabled in flexible-IP mode)
# ---------------------------------------------------------------------------
# resource "scaleway_vpc_connector" "egress_to_hub" {
#   name          = "${local.name_prefix}-conn-egress-to-hub"
#   vpc_id        = module.vpc_egress.id
#   target_vpc_id = local.hub_vpc_id
# }
#
# resource "scaleway_vpc_connector" "hub_to_egress" {
#   name          = "${local.name_prefix}-conn-hub-to-egress"
#   vpc_id        = local.hub_vpc_id
#   target_vpc_id = module.vpc_egress.id
# }

# ---------------------------------------------------------------------------
# Routes - steer spoke traffic through the hub firewall and keep return paths
# ---------------------------------------------------------------------------

# Spokes: 0.0.0.0/0 -> hub, inspected by the central FW (which route-to's
# EGRESS_GROUP + SNATs to the egress VIP).
resource "scaleway_vpc_route" "spoke1_default_to_hub" {
  vpc_id                   = local.spoke1_vpc_id
  description              = "${local.name_prefix}: Spoke-1 default -> Hub firewall"
  tags                     = concat(local.common_tags, ["opnsense", "central-firewall"])
  destination              = "0.0.0.0/0"
  nexthop_vpc_connector_id = local.peering_spoke1_to_hub
}

resource "scaleway_vpc_route" "spoke2_default_to_hub" {
  vpc_id                   = local.spoke2_vpc_id
  description              = "${local.name_prefix}: Spoke-2 default -> Hub firewall"
  tags                     = concat(local.common_tags, ["opnsense", "central-firewall"])
  destination              = "0.0.0.0/0"
  nexthop_vpc_connector_id = local.peering_spoke2_to_hub
}

# Hub <-> egress routes are intentionally absent: the firewalls are
# private-only and spoke egress is policy-routed (route-to EGRESS_PGW), so no
# cross-routes are needed. (Kept as reference from the earlier connector layout.)
# resource "scaleway_vpc_route" "hub_to_egress" {
#   vpc_id                   = local.hub_vpc_id
#   description              = "${local.name_prefix}: Hub -> Egress"
#   tags                     = ["stage3", "egress"]
#   destination              = local.egress_cidr
#   nexthop_vpc_connector_id = scaleway_vpc_connector.hub_to_egress.id
# }
#
# resource "scaleway_vpc_route" "egress_to_hub" {
#   vpc_id                   = module.vpc_egress.id
#   description              = "${local.name_prefix}: Egress -> Hub"
#   tags                     = ["stage3", "egress"]
#   destination              = local.hub_cidr
#   nexthop_vpc_connector_id = scaleway_vpc_connector.egress_to_hub.id
# }
#
# resource "scaleway_vpc_route" "egress_to_spoke_a" {
#   vpc_id                   = module.vpc_egress.id
#   description              = "${local.name_prefix}: Egress -> Spoke A"
#   tags                     = ["stage3", "egress"]
#   destination              = local.spoke_a_cidr
#   nexthop_vpc_connector_id = scaleway_vpc_connector.egress_to_hub.id
# }
#
# resource "scaleway_vpc_route" "egress_to_spoke_b" {
#   vpc_id                   = module.vpc_egress.id
#   description              = "${local.name_prefix}: Egress -> Spoke B"
#   tags                     = ["stage3", "egress"]
#   destination              = local.spoke_b_cidr
#   nexthop_vpc_connector_id = scaleway_vpc_connector.egress_to_hub.id
# }

# Hub steering: default 0.0.0.0/0 -> FW CARP LAN VIP via resource next-hop.
# (A source-based ingress-rule redirect dropped 33-90% of packets in the live
# VPC.) East-west spoke traffic keeps its more-specific 10.20/10.30 hub
# routes, so it flows directly instead of through the FW.
resource "scaleway_vpc_route" "hub_default_to_fw" {
  vpc_id                     = local.hub_vpc_id
  description                = "${local.name_prefix}: Hub default -> FW CARP LAN VIP (steer peered spokes to central FW)"
  tags                       = concat(local.common_tags, ["opnsense", "central-firewall"])
  destination                = "0.0.0.0/0"
  nexthop_private_network_id = local.hub_private_network_ids[local.factory.hub_lan_pn_key]
  nexthop_resource_id        = module.firewall_ha.vip_lan_ipam_id

  # CARP VIP IPAM reservation (created by modules/firewall) must exist and be
  # attached before the route can resolve it.
  depends_on = [module.firewall_ha]
}

# ---------------------------------------------------------------------------
# Firewall management security group
# ---------------------------------------------------------------------------
resource "scaleway_instance_security_group" "firewall_mgmt" {
  count = local.factory.create_firewall_mgmt_sg ? 1 : 0

  name                    = "${local.name_prefix}-firewall-mgmt-sg"
  project_id              = local.project_id
  inbound_default_policy  = "accept"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "1-65535"
    ip_range   = "0.0.0.0/0"
  }
  outbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
  outbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "1-65535"
    ip_range   = "0.0.0.0/0"
  }

  tags = concat(local.common_tags, ["firewall", "management"])
}

# SGs are zone-scoped: fw-passive (fr-par-1) needs its own in AZ1; fw-active
# (fr-par-2) uses the one above. Same rules.
resource "scaleway_instance_security_group" "firewall_mgmt_az1" {
  count = local.factory.create_firewall_mgmt_sg ? 1 : 0

  name                    = "${local.name_prefix}-firewall-mgmt-sg-az1"
  project_id              = local.project_id
  zone                    = local.factory.zones["fw-passive"]
  inbound_default_policy  = "accept"
  outbound_default_policy = "accept"

  inbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
  inbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "1-65535"
    ip_range   = "0.0.0.0/0"
  }
  outbound_rule {
    action   = "accept"
    protocol = "ICMP"
    ip_range = "0.0.0.0/0"
  }
  outbound_rule {
    action     = "accept"
    protocol   = "TCP"
    port_range = "1-65535"
    ip_range   = "0.0.0.0/0"
  }

  tags = concat(local.common_tags, ["firewall", "management"])
}

# ---------------------------------------------------------------------------
# Image import bucket (QCOW2 -> SBS snapshots -> volumes). Lives in the
# lz-<env> project so the ambient key can reach it; the upload-wait gate below
# blocks the snapshot import until the golden qcow2 is present.
# ---------------------------------------------------------------------------
resource "scaleway_object_bucket" "image_import" {
  count      = 1
  name       = local.image_bucket_name
  project_id = local.project_id
  region     = var.region
  tags       = merge(local.common_tags_map, { "firewall-image" = "true" })

  # Empty before destroy: terraform refuses to delete a non-empty bucket
  # (409). Runs with the apply's credentials, falling back to the per-env
  # deploy key file on access-denied, so both `make destroy` and a direct
  # `terraform destroy` empty it cleanly.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      set -euo pipefail
      BUCKET="${self.name}"
      REGION="${self.region}"
      ENDPOINT="https://s3.$${REGION}.scw.cloud"
      export AWS_ACCESS_KEY_ID="$${SCW_ACCESS_KEY:?SCW_ACCESS_KEY must be set}"
      export AWS_SECRET_ACCESS_KEY="$${SCW_SECRET_KEY:?SCW_SECRET_KEY must be set}"
      export AWS_DEFAULT_REGION="$${REGION}"

      # identity fallback (mirrors the upload-wait gate): a destroy may run
      # under an exported key that cannot S3-reach this project's bucket.
      if ! probe="$(aws s3api head-bucket --bucket "$${BUCKET}" --endpoint-url "$${ENDPOINT}" 2>&1)"; then
        case "$${probe}" in
          *AccessDenied*|*Forbidden*|*403*)
            e="$${BUCKET%-image-import-*}"; env="$${e##*-}"
            f="../../../.creds/lz-$${env}.env"
            if [[ -f "$${f}" ]]; then
              echo "note: ambient key cannot reach $${BUCKET} - switching to $(basename "$${f}")"
              export SCW_ACCESS_KEY="$(grep -Eo 'SCW_ACCESS_KEY=[^[:space:]]+' "$${f}" | head -1 | cut -d= -f2-)"
              export SCW_SECRET_KEY="$(grep -Eo 'SCW_SECRET_KEY=[^[:space:]]+' "$${f}" | head -1 | cut -d= -f2-)"
              export AWS_ACCESS_KEY_ID="$${SCW_ACCESS_KEY}"
              export AWS_SECRET_ACCESS_KEY="$${SCW_SECRET_KEY}"
            fi
            ;;
        esac
      fi

      if aws s3api head-bucket --bucket "$${BUCKET}" --endpoint-url "$${ENDPOINT}" >/dev/null 2>&1; then
        echo "==> emptying image-import bucket $${BUCKET} before destroy"
        aws s3 rm "s3://$${BUCKET}" --recursive --endpoint-url "$${ENDPOINT}"
      else
        echo "note: $${BUCKET} not accessible/absent - nothing to empty"
      fi
    EOT
  }
}

# ---------------------------------------------------------------------------
# Upload-wait gate: blocks snapshot import until every golden qcow2 is in the
# bucket. Delivery: bundled file (gate uploads it) > source_url (gate curls) >
# operator-fed (prints exact commands, polls, surfacing the first real S3
# error instead of an opaque 2h wait). Covers every configured object_key.
# ---------------------------------------------------------------------------
resource "null_resource" "upload_wait" {
  depends_on = [scaleway_object_bucket.image_import]

  triggers = {
    bucket      = local.image_bucket_name
    object_keys = join(",", local.upload_wait_keys)
    endpoint    = local.image_s3_endpoint
    bundled     = local.bundled_lines
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      BUCKET="${local.image_bucket_name}"
      ENDPOINT="${local.image_s3_endpoint}"
      KEYS="${join(" ", local.upload_wait_keys)}"
      BUNDLED='${local.bundled_lines}'

      if [ -z "$${KEYS}" ]; then
        echo "No firewall image configured - nothing to wait for."
        exit 0
      fi

      export AWS_ACCESS_KEY_ID="$${SCW_ACCESS_KEY:?SCW_ACCESS_KEY must be set}"
      export AWS_SECRET_ACCESS_KEY="$${SCW_SECRET_KEY:?SCW_SECRET_KEY must be set}"
      export AWS_DEFAULT_REGION="${var.region}"

      # An exported key in the shell ALWAYS wins over the stage's own, so a
      # stage-3 apply can run under one that cannot reach the lz-<env> image
      # bucket. Probe; on access-denied fall back to the per-env deploy key
      # file (.creds/lz-<env>.env) when present.
      REPO_ROOT="$(cd "${path.module}/../../.." && pwd)"
      if ! probe="$(aws s3api list-objects-v2 --bucket "$${BUCKET}" --max-items 1 --endpoint-url "$${ENDPOINT}" 2>&1)"; then
        case "$${probe}" in
          *AccessDenied*|*Forbidden*|*403*)
            f="$${REPO_ROOT}/.creds/lz-${local.environment}.env"
            if [[ -f "$${f}" ]]; then
              echo "note: ambient key cannot reach $${BUCKET} - switching to $(basename "$${f}")"
              export SCW_ACCESS_KEY="$(grep -Eo 'SCW_ACCESS_KEY=[^[:space:]]+' "$${f}" | head -1 | cut -d= -f2-)"
              export SCW_SECRET_KEY="$(grep -Eo 'SCW_SECRET_KEY=[^[:space:]]+' "$${f}" | head -1 | cut -d= -f2-)"
              export AWS_ACCESS_KEY_ID="$${SCW_ACCESS_KEY}"
              export AWS_SECRET_ACCESS_KEY="$${SCW_SECRET_KEY}"
            else
              echo "note: ambient key cannot reach $${BUCKET} and no $${f} to fall back to" >&2
            fi
            ;;
        esac
      fi

      # key -> bundled local path; plain function, not an associative array
      # (macOS ships bash 3.2 in terraform local-exec).
      bundled_path() {
        while IFS='=' read -r k p; do
          [ -n "$${k}" ] || continue
          [ "$${k}" = "$1" ] && { printf '%s' "$${p}"; return 0; }
        done <<< "$${BUNDLED}"
        return 1
      }

      present() { aws s3api head-object --bucket "$${BUCKET}" --key "$1" --endpoint-url "$${ENDPOINT}" >/dev/null 2>&1; }

      # 1) verify each object; auto-push bundled defaults, collect the rest
      operator_required=""
      for k in $${KEYS}; do
        if present "$${k}"; then
          continue
        fi
        p="$(bundled_path "$${k}" || true)"
        if [ -n "$${p}" ]; then
          case "$${p}" in
            url:*)
              U="$${p#url:}"
              echo "==> fetching golden image from source_url: $${U}"
              DL="/tmp/firewall-golden-$${k}"
              rm -f "$${DL}"
              if ! curl -fL --retry 3 --retry-delay 5 -o "$${DL}" "$${U}"; then
                echo "ERROR: failed to download $${U}." >&2
                exit 1
              fi
              if [[ ! -s "$${DL}" ]]; then
                echo "ERROR: downloaded file is empty ($${DL})." >&2
                exit 1
              fi
              echo "    downloaded $(stat -f%z "$${DL}" 2>/dev/null || stat -c%s "$${DL}" 2>/dev/null) bytes"
              echo "    -> uploading to s3://$${BUCKET}/$${k}"
              if ! aws s3 cp "$${DL}" "s3://$${BUCKET}/$${k}" --endpoint-url "$${ENDPOINT}"; then
                echo "ERROR: failed to upload downloaded image to s3://$${BUCKET}/$${k}." >&2
                exit 1
              fi
              rm -f "$${DL}"
              ;;
            *)
              echo "==> auto-uploading bundled default image: $${p}"
              echo "    -> s3://$${BUCKET}/$${k}"
              if ! aws s3 cp "$${p}" "s3://$${BUCKET}/$${k}" --endpoint-url "$${ENDPOINT}"; then
                echo "ERROR: failed to upload bundled image $${p}." >&2
                echo "       The key in use cannot write s3://$${BUCKET}. Run the apply with the" >&2
                echo "       lz-${local.environment} key - unset exported SCW_* then:" >&2
                echo "         set -a; source .creds/lz-${local.environment}.env; set +a" >&2
                exit 1
              fi
              ;;
          esac
          if present "$${k}"; then
            echo "    uploaded OK"
          else
            echo "ERROR: object still not visible after upload (wrong ambient key / project scope?)." >&2
            exit 1
          fi
        else
          operator_required="$${operator_required} $${k}"
        fi
      done

      if [ -z "$${operator_required}" ]; then
        echo "All firewall image object(s) present (bundled defaults auto-uploaded where needed)."
        echo "Proceeding with snapshot import."
        exit 0
      fi

      # 2) operator-fed images: print the upload instructions and poll.
      echo ""
      echo "==============================================================="
      echo " UPLOAD REQUIRED: golden firewall image(s) missing from s3://$${BUCKET}"
      echo " expected object(s):$${operator_required}"
      echo " Upload them now with a key defaulted to the lz-${local.environment} project:"
      echo ""
      echo "   set -a; source .creds/lz-${local.environment}.env; set +a"
      for k in $${operator_required}; do
        echo "   aws s3 cp <path>/$${k} s3://$${BUCKET}/$${k} --endpoint-url $${ENDPOINT}"
      done
      echo ""
      echo " Waiting for s3://$${BUCKET}/$${operator_required# } (polling every 15s)..."
      echo "   (first failure prints the real S3 error - 403 = wrong key, 404 = wrong name)"
      echo "==============================================================="
      echo ""

      reported=0
      for i in $(seq 1 480); do  # up to 2 hours
        missing=""
        for k in $${operator_required}; do
          if ! present "$${k}"; then
            missing="$${missing} $${k}"
          fi
        done
        if [ -z "$${missing}" ]; then
          echo "Image(s) present - proceeding with snapshot import."
          exit 0
        fi
        if [ "$${reported}" -eq 0 ]; then
          echo "Missing object(s):$${missing}"
          for k in $${missing}; do
            err="$(aws s3api head-object --bucket "$${BUCKET}" --key "$${k}" --endpoint-url "$${ENDPOINT}" 2>&1 >/dev/null || true)"
            echo "  head-object $${k} -> $${err}" | head -c 400
            echo ""
          done
          echo "  Note: 403 = wrong ambient key (unset exported SCW_*, use .creds/lz-${local.environment}.env); 404 = object not uploaded under the configured name above"
          reported=1
        fi
        sleep 15
      done
      echo "ERROR: timed out waiting for upload to s3://$${BUCKET} (2h)." >&2
      exit 1
    EOT
  }
}

module "firewall_image_1" {
  source = "../../../modules/firewall-image"
  count  = local.fw_image_1 != null ? 1 : 0

  # Force bucket creation first; never start the long snapshot import before
  # the qcow2 is in the bucket (upload-wait gate).
  depends_on = [scaleway_object_bucket.image_import, null_resource.upload_wait]

  vendor            = local.fw_image_1.vendor
  appliance_version = local.fw_image_1.version
  project_id        = local.project_id
  region            = var.region
  zones             = local.fw_image_1.zones
  snapshot_size     = local.fw_image_1.snapshot_size

  # Stage-3 owns the bucket + snapshots, never derive from an external snapshot.
  snapshot_id_override = ""

  source_url        = local.fw_image_1.source_url
  source_format     = local.fw_image_1.source_format
  object_key        = local.fw_image_1.object_key
  bucket_name       = local.image_bucket_name
  s3_endpoint       = local.fw_image_1.s3_endpoint
  enable_upload     = local.fw_image_1.enable_upload
  force_download    = local.fw_image_1.force_download
  force_upload      = local.fw_image_1.force_upload
  upload_access_key = local.fw_image_1.upload_access_key
  upload_secret_key = local.fw_image_1.upload_secret_key

  tags = local.common_tags
}

module "firewall_image_2" {
  source = "../../../modules/firewall-image"
  count  = local.fw_image_2 != null ? 1 : 0

  # Force bucket creation first; never start the long snapshot import before
  # the qcow2 is in the bucket (upload-wait gate).
  depends_on = [scaleway_object_bucket.image_import, null_resource.upload_wait]

  vendor            = local.fw_image_2.vendor
  appliance_version = local.fw_image_2.version
  project_id        = local.project_id
  region            = var.region
  zones             = local.fw_image_2.zones
  snapshot_size     = local.fw_image_2.snapshot_size

  # Stage-3 owns the bucket + snapshots, never derive from an external snapshot.
  snapshot_id_override = ""

  source_url        = local.fw_image_2.source_url
  source_format     = local.fw_image_2.source_format
  object_key        = local.fw_image_2.object_key
  bucket_name       = local.image_bucket_name
  s3_endpoint       = local.fw_image_2.s3_endpoint
  enable_upload     = local.fw_image_2.enable_upload
  force_download    = local.fw_image_2.force_download
  force_upload      = local.fw_image_2.force_upload
  upload_access_key = local.fw_image_2.upload_access_key
  upload_secret_key = local.fw_image_2.upload_secret_key

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Test instances - validate VPC peering / transitivity / FW policy
# (hub-test, spoke-1-test, spoke-2-test)
# ---------------------------------------------------------------------------
module "test_instances" {
  source   = "../../../modules/instance-vm"
  for_each = local.factory.create_test_instances ? local.test_instances : {}

  name              = "${local.name_prefix}-${each.value.name}"
  instance_type     = lookup(each.value, "instance_type", "DEV1-S")
  image             = lookup(each.value, "image", "ubuntu_jammy")
  project_id        = local.project_id
  zone              = coalesce(each.value.zone, var.zone)
  tags              = concat(local.common_tags, lookup(each.value, "tags", ["test"]))
  security_group_id = data.terraform_remote_state.stage1.outputs.security_group_ids[lookup(each.value, "security_group_key", "internal-sg")]
  enable_dynamic_ip = lookup(each.value, "enable_dynamic_ip", false)
  ips               = lookup(each.value, "ips", {})

  private_networks = {
    pn = {
      pn_id   = data.terraform_remote_state.stage2.outputs.private_network_ids[each.value.vpc_key][each.value.private_network_key]
      ipam_ip = try(each.value.lan_ip, null) # static pin for hub-test (null = DHCP)
    }
  }

  # Rebuild ordering: the instance's DHCP default route only appears after
  # hub_default_to_fw exists (its next-hop is the FW LAN VIP). Without this, a
  # fresh apply can boot hub-test before the route, leaving it dark up to 1h.
  depends_on = [scaleway_vpc_route.hub_default_to_fw]

  # Admin SSH key from bootstrap + public-IP reply policy routing: with both a
  # flexible public IP and a private NIC, the private DHCP default shadows
  # the public one and the platform blackholes inbound, source-based rule
  # (table 200) sends /32 replies out the public NIC. Idempotent via systemd.
  user_data = {
    "cloud-init" = <<-EOT
      #cloud-config
      ssh_authorized_keys:
        - ${trimspace(data.terraform_remote_state.bootstrap.outputs.ssh_public_keys["admin_key"])}

      write_files:
        - path: /usr/local/sbin/ensure-public-reply-routes.sh
          permissions: '0755'
          content: |
            #!/usr/bin/env bash
            # Public flexible IP + private NIC: policy-route reply traffic
            # (source = public /32) out the public NIC via table 200, the
            # private-NIC DHCP default (lower metric) otherwise blackholes ALL
            # inbound. Runs at every boot (systemd oneshot); idempotent.
            set -u
            PUBDEV=""
            PUB=""
            GW=""
            for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
              line=$(ip -4 -o addr show scope global 2>/dev/null | awk '$4 ~ /\/32$/ {print; exit}')
              if [ -n "$line" ]; then
                PUBDEV=$(printf '%s\n' "$line" | awk '{print $2}')
                PUB=$(printf '%s\n' "$line" | awk '{split($4,a,"/"); print a[1]}')
                break
              fi
              sleep 5
            done
            if [ -z "$PUBDEV" ]; then
              echo "no public /32 address -- internal-only instance, nothing to do"
              exit 0
            fi
            for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
              GW=$(ip -4 route show default 2>/dev/null | awk -v d="$PUBDEV" '$1=="default" && $4=="dev" && $5==d {print $3; exit}')
              if [ -n "$GW" ]; then break; fi
              sleep 5
            done
            if [ -z "$GW" ]; then
              echo "no default gateway on $PUBDEV yet -- will retry on next boot"
              exit 1
            fi
            ip route replace default via "$GW" dev "$PUBDEV" table 200
            ip rule del from "$PUB"/32 lookup 200 prio 1000 2>/dev/null || true
            ip rule add from "$PUB"/32 lookup 200 prio 1000
            echo "public reply route ensured: $PUB -> table 200 via $GW dev $PUBDEV"
        - path: /etc/systemd/system/ensure-public-reply-routes.service
          permissions: '0644'
          content: |
            [Unit]
            Description=Ensure public-IP reply routes (flexible IP policy routing)
            After=network-online.target
            Wants=network-online.target
            [Service]
            Type=oneshot
            ExecStart=/usr/local/sbin/ensure-public-reply-routes.sh
            [Install]
            WantedBy=multi-user.target
        # Self-heal: networkd/IPAM churn can flush table 200 after boot, so a
        # timer re-runs the script every 2 min. No RemainAfterExit, that
        # would keep the unit "active" and make each timer fire a no-op.
        - path: /etc/systemd/system/ensure-public-reply-routes.timer
          permissions: '0644'
          content: |
            [Unit]
            Description=Periodically re-ensure public-IP reply routes
            [Timer]
            OnBootSec=2min
            OnUnitActiveSec=2min
            Unit=ensure-public-reply-routes.service
            [Install]
            WantedBy=timers.target

      runcmd:
        - systemctl daemon-reload
        - systemctl enable --now ensure-public-reply-routes.service
        - systemctl enable --now ensure-public-reply-routes.timer
    EOT
  }
}
