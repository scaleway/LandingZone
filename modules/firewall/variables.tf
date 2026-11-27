# ---------------------------------------------------------------------------
# HA-Firewall Module, Input Variables
# ---------------------------------------------------------------------------

variable "vendor" {
  description = "Firewall vendor. Only opnsense is supported (pfsense/fortigate/paloalto/stormshield are planned add-ons)."
  type        = string
  validation {
    condition     = var.vendor == "opnsense"
    error_message = "Vendor must be: opnsense."
  }
}

variable "organization_id" {
  description = "Scaleway organization ID. Exported as SCW_DEFAULT_ORGANIZATION_ID to the scw CLI local-exec calls."
  type        = string
}

variable "project_id" {
  description = "Scaleway project ID to deploy into."
  type        = string
}

variable "region" {
  description = "Scaleway region (e.g., fr-par)."
  type        = string
  default     = "fr-par"
}

variable "environment" {
  description = "Environment tag (e.g., dev, prod)."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Firewall zoning (cross-AZ HA)
# ---------------------------------------------------------------------------

variable "zones" {
  description = "Zones for passive and active firewalls. If unset, derives from snapshot_ids map keys."
  type = object({
    fw_passive = optional(string, null)
    fw_active  = optional(string, null)
  })
  default = {
    fw_passive = null
    fw_active  = null
  }
}

variable "snapshot_ids" {
  description = "Map of zone => object containing volume_id and size_gb for the firewall image."
  type = map(object({
    volume_id = string
    size_gb   = number
  }))
}

variable "instance_type" {
  description = "Scaleway instance type for firewall VMs."
  type        = string
  default     = "POP2-2C-8G"
}

# ---------------------------------------------------------------------------
# Network IDs (provided by the caller, VPCs/PNs created elsewhere)
# ---------------------------------------------------------------------------

variable "lan_vpc_id" {
  description = "VPC ID for the LAN (trusted) network."
  type        = string
}

variable "lan_private_network_ids" {
  description = "Map of LAN Private Network IDs keyed by name."
  type        = map(string)
}

variable "lan_pn_key" {
  description = "Key in lan_private_network_ids for the LAN (trusted) network."
  type        = string
  default     = "hub-net"
}

variable "lan_cidr" {
  description = "CIDR of the LAN private network."
  type        = string
}

variable "wan_vpc_id" {
  description = "VPC ID for the WAN (untrusted) network(s). Optional: when no WAN private network is provided (flexible-IP mode), null."
  type        = string
  default     = null
}

variable "wan_private_network_ids" {
  description = "Map of WAN Private Network IDs keyed by name (e.g., wan1, wan2). Empty map => flexible-IP WAN (public IP on the main NIC, no WAN PN)."
  type        = map(string)
  default     = {}
}

variable "wan_pn_keys" {
  description = "Keys in wan_private_network_ids for WAN network(s). First is primary. Empty list => flexible-IP WAN."
  type        = list(string)
  default     = []
}

variable "wan_cidr" {
  description = "CIDR of the primary WAN private network. Optional when no WAN PN is used."
  type        = string
  default     = null
}

variable "ha_vpc_id" {
  description = "VPC ID for the HA (heartbeat/sync) networks."
  type        = string
}

variable "ha_private_network_ids" {
  description = "Map of HA Private Network IDs keyed by name (e.g., heartbeat, sync)."
  type        = map(string)
}

variable "ha_pn_key" {
  description = "Key in ha_private_network_ids for the HA/heartbeat/sync network."
  type        = string
  default     = "sync"
}

# ---------------------------------------------------------------------------
# Flexible public IPs (optional)
# When set, the given flexible public IP is attached to the server (WAN = the
# routed main NIC, vtnet0). In flexible-IP mode no WAN private network should
# be provided, see wan_private_network_ids.
# ---------------------------------------------------------------------------

variable "fw_passive_ip_id" {
  description = "Optional flexible public IP resource ID to attach to firewall 1 (the WAN becomes the routed main NIC)."
  type        = string
  default     = null
}

variable "fw_active_ip_id" {
  description = "Optional flexible public IP resource ID to attach to firewall 2 (the WAN becomes the routed main NIC)."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Security group (from Stage 1)
# ---------------------------------------------------------------------------

variable "security_group_ids" {
  description = "Map of security group IDs. Preferred keys: fw_passive / fw_active (per-node, zone-scoped SGs). Legacy key: firewall_mgmt (single SG, used as fallback)."
  type        = map(string)
}

# ---------------------------------------------------------------------------
# IPAM addresses, structured maps with role keys
# fw_passive_ips / fw_active_ips must contain: wan, lan, ha (and optionally wan2)
# vip_ips must contain: wan, lan
# ---------------------------------------------------------------------------

variable "fw_passive_ips" {
  description = "Map of role => IP address for firewall 1 (keys: wan, lan, ha, ha2, wan2, mgmt optional)."
  type = object({
    wan  = string
    lan  = string
    ha   = string
    ha2  = optional(string, null)
    wan2 = optional(string, null)
    mgmt = optional(string, null)
  })
}

variable "fw_active_ips" {
  description = "Map of role => IP address for firewall 2 (keys: wan, lan, ha, ha2, wan2, mgmt optional)."
  type = object({
    wan  = string
    lan  = string
    ha   = string
    ha2  = optional(string, null)
    wan2 = optional(string, null)
    mgmt = optional(string, null)
  })
}

variable "vip_ips" {
  description = "Map of role => Virtual IP address (keys: wan, lan) for CARP vendors (opnsense)."
  type = object({
    wan = optional(string, null)
    lan = optional(string, null)
  })
  default = {
    wan = null
    lan = null
  }
}

# ---------------------------------------------------------------------------
# Behaviour flags
# ---------------------------------------------------------------------------

variable "enable_vips" {
  description = "Enable CARP virtual IPs (only for opnsense)."
  type        = bool
  default     = false
}

variable "vip_wan_mac" {
  description = "Custom-resource MAC for the WAN/egress CARP VIP. Must match the CARP vhid used in the appliance config (00:00:5e:00:01:<vhid-hex>)."
  type        = string
  default     = "00:00:5E:00:01:01"
}

variable "vip_lan_mac" {
  description = "Custom-resource MAC for the LAN CARP VIP. Must match the CARP vhid used in the appliance config (00:00:5e:00:01:<vhid-hex>)."
  type        = string
  default     = "00:00:5E:00:01:03"
}

variable "create_default_routes" {
  description = "Whether to create 0.0.0.0/0 routes in LAN and WAN VPCs pointing to the firewall VIPs/NICs."
  type        = bool
  default     = true
}

variable "create_test_instances" {
  description = "Whether to create LAN/WAN ping test servers."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Vendor config files (pulled from the HA-firewalls training repo)
# Injected into firewall instances as cloud-init user-data on first boot.
# ---------------------------------------------------------------------------

variable "config_paths" {
  description = "Map of vendor => path to vendor-specific config backup files. For OPNsense, opnsense_fw_passive / opnsense_fw_active point to the caller-rendered per-node XML files (injected via user_data['opnsense_config'])."
  type = object({
    opnsense_fw_passive = optional(string)
    opnsense_fw_active  = optional(string)
  })
  default = null
}

variable "admin_pubkey" {
  description = "SSH public key to inject into the firewall admin user's authorized_keys. Pass an empty string if not needed."
  type        = string
  default     = ""
}

variable "fw_passive_config_xml" {
  description = "Pre-rendered OPNsense config XML for the passive node (string). Preferred over config_paths.opnsense_fw_passive, mirrors the blueprint firewall-ha module and avoids plan-time file() dependencies."
  type        = string
  default     = null
  nullable    = true
}

variable "fw_active_config_xml" {
  description = "Pre-rendered OPNsense config XML for the active node (string). Preferred over config_paths.opnsense_fw_active."
  type        = string
  default     = null
  nullable    = true
}

# ---------------------------------------------------------------------------
# Extra user-data (per node), merged into the firewall instances' user_data
# WITHOUT touching the opnsense_config XML key. This is the light-weight
# channel for per-node tweaks (cloud-init scripts: sysctl, Syslog, extra
# rules) that must not re-render the XML template - changing opnsense_config
# reboots the whole HA pair (partner feedback, issue #14).
# ---------------------------------------------------------------------------

variable "extra_user_data_passive" {
  description = "Extra user-data keys for the passive node (map key => content), merged into the instance user_data alongside opnsense_config. Leave empty for none."
  type        = map(string)
  default     = {}
}

variable "extra_user_data_active" {
  description = "Extra user-data keys for the active node (map key => content), merged into the instance user_data alongside opnsense_config. Leave empty for none."
  type        = map(string)
  default     = {}
}


# ---------------------------------------------------------------------------
# Optional management network and second HA network (generic optional
# attachments; historically used by non-CARP firewall vendors).
# ---------------------------------------------------------------------------

variable "management_private_network_ids" {
  description = "Map of Management Private Network IDs keyed by name."
  type        = map(string)
  default     = {}
}

variable "management_pn_key" {
  description = "Key in management_private_network_ids for the management network."
  type        = string
  default     = "management"
}

# ---------------------------------------------------------------------------
# Dual HA networks (optional, generic second sync network)
# ---------------------------------------------------------------------------

variable "ha2_private_network_ids" {
  description = "Map of second HA Private Network IDs keyed by name (optional second sync network)."
  type        = map(string)
  default     = {}
}

variable "ha2_pn_key" {
  description = "Key in ha2_private_network_ids for the second HA network."
  type        = string
  default     = "sync"
}

# Optional informational vars (accepted but not referenced by module logic)
variable "name" {
  description = "Optional display name for the HA firewall pair (informational)."
  type        = string
  default     = null
}

variable "ha_cidr" {
  description = "CIDR of the HA sync private network (informational)."
  type        = string
  default     = null
}
