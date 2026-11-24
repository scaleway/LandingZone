/**
 * fw-restore drill (stage 2 of the restore-drill plan, see ../../RTO-RPO.md).
 * Proves the cold-restore path for the HA OPNsense pair: the last DR-bucket
 * config export is injected into two scratch nodes booted from the same
 * golden image + first-boot import path as production, then timed and verified
 * (configd applied, CARP formed) by a cloud-side probe. Everything lives in
 * its own scratch VPCs; `terraform destroy` removes the whole scaffold,
 * production volumes are never referenced. Usage mirrors the other stages
 * (see the stage README): init with the env backend, apply with the env tfvars.
 */

terraform {
  required_version = ">= 1.5"
  required_providers {
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    key = "stage-5-drill/terraform.tfstate"
  }
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = var.infra_ops_project_id
  region          = var.region
  zone            = var.zone
}

# Stage-3 state: reference only, the drill boots its own volumes from the
# same golden object (distinct names).
data "terraform_remote_state" "stage3" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-3/terraform.tfstate"
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

# Stage-5 state: the probe reuses the exporter's serverless namespace
# (overridable via probe_namespace_id).
data "terraform_remote_state" "stage5" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    region = var.region
    key    = "stage-5/terraform.tfstate"
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

locals {
  # Scratch address plan mirrors production (the restored DR config references
  # those exact addresses). -demo factory file preferred; committed fallback.
  factory_file = fileexists("${path.module}/../../../../envs/${var.environment}/data/security-appliances-${var.environment}-demo.yaml") ? "${path.module}/../../../../envs/${var.environment}/data/security-appliances-${var.environment}-demo.yaml" : "${path.module}/../../../../envs/${var.environment}/data/security-appliances-${var.environment}.yaml"

  factory = yamldecode(file(local.factory_file))

  lan_cidr = local.factory.hub_subnet_cidr
  wan_cidr = local.factory.egress_cidr
  ha_cidr  = local.factory.ha_sync_cidr

  fw_passive_ips = { wan = local.factory.ipam.egress["fw-passive"], lan = local.factory.ipam.lan["fw-passive"], ha = local.factory.ipam.sync["fw-passive"] }
  fw_active_ips  = { wan = local.factory.ipam.egress["fw-active"], lan = local.factory.ipam.lan["fw-active"], ha = local.factory.ipam.sync["fw-active"] }
  vip_ips        = { wan = local.factory.ipam.egress.vip, lan = local.factory.ipam.lan.vip }

  # CARP vhids 10 (LAN) / 11 (egress) - matches the restored config.
  vip_lan_mac = local.factory.ipam.vmacs.lan
  vip_wan_mac = local.factory.ipam.vmacs.egress

  # Probe targets from the factory ipam (matches the live CARP pair).
  fw_hosts = "${local.factory.ipam.lan["fw-passive"]},${local.factory.ipam.lan["fw-active"]}"

  # Golden image snapshots by ID from stage-3 state, names can collide across
  # rebuilds, so never look them up by name.
  golden_snapshot_ids = data.terraform_remote_state.stage3.outputs.golden_snapshot_ids

  # Restored config XMLs (gitignored, fetched from the DR bucket by the drill
  # operator) + the firewall backup SSH key for the cloud-side probe.
  restore_fw_passive = file(coalesce(var.restore_fw_passive_xml_file, "${path.module}/restore/fw_passive.xml"))
  restore_fw_active  = file(coalesce(var.restore_fw_active_xml_file, "${path.module}/restore/fw_active.xml"))
  backup_key         = file(coalesce(var.fw_backup_key_file, "${path.module}/../../../../keys-${var.environment}/fw-backup/id_ed25519"))

  # Serverless namespace for the probe - reuse the stage-5 exporter namespace
  # unless explicitly overridden.
  probe_namespace_id = var.probe_namespace_id != "" ? var.probe_namespace_id : data.terraform_remote_state.stage5.outputs.fw_exporter_namespace_id
}

# ---------------------------------------------------------------------------
# Scratch VPC + Private Networks + permissive per-zone security groups.
# ---------------------------------------------------------------------------
module "drill_vpc" {
  source = "../../../../../modules/vpc"

  name       = "lz-${var.environment}-drill"
  project_id = var.infra_ops_project_id
  region     = var.region
  tags       = ["drill", "restore", "temporary"]

  private_networks = {
    lan = { name = "lz-${var.environment}-drill-lan", ipv4_subnet_cidr = local.lan_cidr }
    wan = { name = "lz-${var.environment}-drill-wan", ipv4_subnet_cidr = local.wan_cidr }
    ha  = { name = "lz-${var.environment}-drill-ha", ipv4_subnet_cidr = local.ha_cidr }
  }

  # Zone matches the drill nodes (fw-passive fr-par-1 / fw-active fr-par-2).
  # Permissive, the drill needs no platform SG rules.
  security_groups = {
    sg_1 = {
      name                    = "lz-${var.environment}-drill-sg-1"
      zone                    = var.drill_zone_fw_passive
      stateful                = true
      enable_default_security = false
      inbound_default_policy  = "accept"
      outbound_default_policy = "accept"
      tags                    = ["drill"]
    }
    sg_2 = {
      name                    = "lz-${var.environment}-drill-sg-2"
      zone                    = var.drill_zone_fw_active
      stateful                = true
      enable_default_security = false
      inbound_default_policy  = "accept"
      outbound_default_policy = "accept"
      tags                    = ["drill"]
    }
  }
}

# ---------------------------------------------------------------------------
# Drill boot volumes: fresh clones of the production golden snapshots (by ID,
# names can collide across rebuilds). Snapshot clone avoids the image bucket
# (hardened, 403 on it) and beats a fresh import. Volumes are the drill's own,
# so destroy never touches production snapshots or volumes.
# ---------------------------------------------------------------------------
resource "scaleway_block_volume" "drill" {
  for_each = toset([var.drill_zone_fw_passive, var.drill_zone_fw_active])

  name        = "${local.factory.firewall_image_1.vendor}-${local.factory.firewall_image_1.version}-drill-vol-${index([var.drill_zone_fw_passive, var.drill_zone_fw_active], each.key) + 1}"
  size_in_gb  = var.fw_snapshot_size
  iops        = 5000
  zone        = each.key
  snapshot_id = local.golden_snapshot_ids[each.key]
  tags        = ["drill", "restore", "temporary"]
}

# ---------------------------------------------------------------------------
# Restored HA pair, same module + first-boot import path as production, with
# the DR-restored XML. No 0/0 routes (create_default_routes=false).
# ---------------------------------------------------------------------------
module "fw_restore" {
  source = "../../../../../modules/firewall"

  vendor          = "opnsense"
  project_id      = var.infra_ops_project_id
  region          = var.region
  environment     = var.environment
  tags            = ["drill", "restore", "temporary"]
  organization_id = var.organization_id

  zones = {
    fw_passive = var.drill_zone_fw_passive
    fw_active  = var.drill_zone_fw_active
  }

  snapshot_ids = {
    for z in [var.drill_zone_fw_passive, var.drill_zone_fw_active] : z => {
      volume_id = "${z}/${split("/", scaleway_block_volume.drill[z].id)[1]}"
      size_gb   = var.fw_snapshot_size
    }
  }
  instance_type = var.fw_instance_type

  lan_vpc_id = module.drill_vpc.id
  lan_private_network_ids = {
    "drill-lan" = module.drill_vpc.private_network_ids["lan"]
  }
  lan_pn_key = "drill-lan"
  lan_cidr   = local.lan_cidr

  wan_vpc_id = module.drill_vpc.id
  wan_private_network_ids = {
    "drill-wan" = module.drill_vpc.private_network_ids["wan"]
  }
  wan_pn_keys = ["drill-wan"]
  wan_cidr    = local.wan_cidr

  ha_vpc_id = module.drill_vpc.id
  ha_private_network_ids = {
    "drill-ha" = module.drill_vpc.private_network_ids["ha"]
  }
  ha_pn_key = "drill-ha"

  security_group_ids = {
    fw_passive = module.drill_vpc.security_group_ids["sg_1"]
    fw_active  = module.drill_vpc.security_group_ids["sg_2"]
  }

  fw_passive_ips = local.fw_passive_ips
  fw_active_ips  = local.fw_active_ips
  vip_ips        = local.vip_ips
  enable_vips    = true
  vip_wan_mac    = local.vip_wan_mac
  vip_lan_mac    = local.vip_lan_mac

  create_default_routes = false

  fw_passive_config_xml = local.restore_fw_passive
  fw_active_config_xml  = local.restore_fw_active
}

# ---------------------------------------------------------------------------
# Cloud-side probe: private container on the drill LAN PN, SSH-probes the
# restored pair (hostname / LAN IP / configd / CARP) over HTTP. Same pattern
# + namespace as the prod exporter; invoke with the backup SA's X-Auth-Token.
# No cron trigger.
# ---------------------------------------------------------------------------
module "fw_probe" {
  source = "../../../../../modules/serverless-container"

  name        = "lz-${var.environment}-drill-probe"
  description = "Restore-drill probe (scratch LAN PN, SSH status check)"
  project_id  = var.infra_ops_project_id
  region      = var.region
  tags        = ["drill", "restore", "temporary"]

  create_namespace = false
  namespace_id     = local.probe_namespace_id

  image        = "alpine:3.20"
  port         = 8080
  protocol     = "http1"
  privacy      = "private"
  min_scale    = 0
  max_scale    = 1
  cpu_limit    = 140
  memory_limit = 256
  timeout      = 300

  private_network_id = module.drill_vpc.private_network_ids["lan"]

  command = ["/bin/sh", "-c", file("${path.module}/../../files/fw-tool.sh")]

  environment_variables = {
    "MODE"     = "probe"
    "FW_HOSTS" = local.fw_hosts
    "FW_USER"  = "root"
  }

  secret_environment_variables = {
    "FW_SSH_KEY" = local.backup_key
  }
}
