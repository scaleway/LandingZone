# HA-Firewall Module

Deploys a high-availability firewall pair on Scaleway across two availability zones.
Supports the CARP-based vendor `opnsense` (other vendors such as
fortigate/paloalto/stormshield are planned add-ons, tracked as GitHub issues).

## How it works

- **fw-passive** is placed in `fr-par-1`, **fw-active** in `fr-par-2` (cross-AZ
  HA).
- Each node boots from a **snapshot** of the firewall's image (per-zone volume).
- Both nodes attach to the same **WAN**, **LAN**, and **HA-sync** Private Networks.
- The active node is the one whose Private NIC the VPC routes point to.
- For **opnsense**, CARP Virtual IPs are created via `custom_resource` MAC addresses
  (`00:00:5E:00:01:01`/`00:00:5E:00:01:03`) and VPC routes point to them, so either node
  can own the VIP at runtime.

## Config files

The module bundles the tested vendor configuration backups from the `HA-firewalls/`
training repo under `config/<vendor>/`:

| Vendor   | File                           | Used for                          |
|----------|--------------------------------|-----------------------------------|
| opnsense | `config/opnsense/fw_passive.xml` | `cloud-init` => `fw-passive`    |
| opnsense | `config/opnsense/fw_active.xml`  | `cloud-init` => `fw-active`     |

Override with `var.config_paths` to use your own configs.

## Usage

```hcl
module "ha_firewall" {
  source = "../../../modules/ha-firewall"

  vendor     = "opnsense"
  project_id = "..."
  region     = "fr-par"
  environment = "dev"

  lan_vpc_id            = module.vpc_hub.id
  lan_private_network_ids = module.vpc_hub.private_network_ids
  lan_pn_key            = "hub-net"

  wan_vpc_id              = module.vpc_egress.id
  wan_private_network_ids = module.vpc_egress.private_network_ids
  wan_pn_keys             = ["wan1", "wan2"]

  ha_vpc_id              = module.vpc_ha.id
  ha_private_network_ids = module.vpc_ha.private_network_ids
  ha_pn_key              = "sync"

  snapshot_ids  = var.firewall_config.snapshot_ids
  instance_type = var.firewall_config.instance_type

  fw_passive_ips = { wan = "192.168.0.251", lan = "10.10.0.251", ha = "10.0.25.3" }
  fw_active_ips  = { wan = "192.168.0.252", lan = "10.10.0.252", ha = "10.0.25.2" }

  vip_ips     = { wan = "192.168.0.253", lan = "10.10.0.253" }
  enable_vips = true
}
```
