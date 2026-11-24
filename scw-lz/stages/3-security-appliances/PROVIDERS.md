# Stage 3 - Firewall provider add-ons (multi-vendor)

How a vendor (OPNsense, pfSense, FortiGate, Palo Alto, ...) plugs into Stage 3,
and how a user selects it. The north star stays the same whatever the vendor:
the hub/spoke + PAT door + egress plane + floating-VIP steering plumbing, with
only the appliance, its config artifact, its boot image and its test battery
changing.

## Selection

```hcl
# scw-lz/stages/3-security-appliances/terraform.tfvars
firewall_provider = "opnsense"   # one of: opnsense | pfsense | fortigate | paloalto | stormshield
```

- Default is `opnsense` - the deployed reference implementation.
- Only `opnsense` is wired end-to-end today. Any other value fails
  `terraform plan` with a clear message (`provider_wired_guard` precondition)
  until that provider's add-on is implemented (roadmap below).

## What does NOT change between providers (the shared contract)

The stage owns all of this once, vendor-agnostically:

| Piece | Where |
|---|---|
| hub/spoke VPCs, private networks, IPAM reservations, static addresses | Stage 2 + `main.tf` |
| **Dual-gateway failover plumbing** | `main.tf` + per-provider template |
| PAT **door** at the hub PGW (management plane; per-provider port map) | `main.tf` |
| **Egress plane** (egress PGWs `10.4.0.2` fr-par-2 + `10.4.0.3` fr-par-1, masquerade `51.159.145.9`) | `main.tf` |
| Hub steering `0.0.0.0/0 -> FW floating VIP` (a VIP is a VIP) | `main.tf` + module |
| HA **sync VPC** (pfsync/XMLRPC for CARP vendors; heartbeat for FGCP/PAN) | `main.tf` + module |
| Instance/NIC plumbing | `modules/firewall` (vendor-parameterized) |
| Golden image pipeline | `modules/firewall-image` (generic: `vendor`, `source_url`, `version`) |
| Deterministic IPAM + rebuild story | stage + module |

## Dual-gateway interface (the AZ-redundancy contract)

Every plane (hub door + egress) runs **two public gateways on the same
private network**: the primary in the tenants' zone (`var.zone`, fr-par-2) and
the alt in the opposite zone (fr-par-1). The stage core creates them -
vendor-agnostic Scaleway resources. What a provider template receives is a
plain **ordered gateway IP list**, nothing else:

| Template variable | Type | Meaning |
|---|---|---|
| `hub_gateways` | `list(string)` | Hub door PGW LAN IPs, `[primary, alt]` (alt optional) |
| `egress_gateways` | `list(string)` | Egress PGW LAN IPs, `[primary, alt]` (alt optional) |

How the failover is expressed stays 100% vendor-side:

| Vendor | Failover mechanism |
|---|---|
| OPNsense / pfSense | gateway group (tier 1 = primary, tier 2 = alt) + dpinger monitors; default route / route-to / reply routes point at the group |
| FortiGate | dual-WAN SD-WAN (cost/health based) - needs a second WAN plane per gateway (see the roadmap note) |

The shared rules: primary first in the list; the list length is 1 in a
single-PGW env (template degrades, no alt gateway); never push a platform
default from either gateway (`push_default_route = false`); the public egress
IP changes on failover (acceptable - documented). The door is active/passive:
the stage exposes both door public IPs (`door_ip` / `door_ip_alt`), the
operator switches to the alt when the primary dies (Scaleway PAT is
DNAT-only, replies must leave through the door the client entered).

## What a provider add-on must deliver

| Artifact | OPNsense (reference ) | Add-on contract |
|---|---|---|
| Selector | `firewall_provider = "opnsense"` | a new valid value in `variables.tf` validation |
| Module mapping | `vendor = var.firewall_provider` | none (module already branches on `vendor`) |
| **HA model** | CARP (vhid 10/11 + IPAM VIPs) | CARP (pfSense), FGCP + `failover.tf` IPAM function (FortiGate), active/passive (Palo Alto) |
| **Config artifact** | `providers/opnsense/opnsense-config.xml.tftpl` -> `fw_passive/active_config_xml` (native `user_data` import) | `providers/<vendor>/<config>.tftpl`, rendered per node, plus its injection method |
| **Boot image** | OPNsense golden QCOW2 via `firewall_image_1/2` | per-vendor golden (`source_url` + `version` in tfvars) |
| **Mgmt door map** | WebUI `:8443/:8444/:8445`, SSH `:8022/:8023` | per-vendor plan (all vendors: SSH 22 + HTTPS 443) |
| **Test battery** | `providers/opnsense/test-firewalls.sh` | `providers/<vendor>/test-<vendor>.sh` (vendor CLI) |
| **Docs** | this stage's README | `providers/<vendor>/README.md` |

Config rendering must follow the existing rule: content is passed to the module
as **locals** (`fw_passive_config_xml`/`fw_active_config_xml`) - no plan-time
`file()` dependency on files that only exist at apply time.

## Provider status & roadmap

| Provider | HA | Config injection | Licensing | Status |
|---|---|---|---|---|
| **OPNsense** | CARP | native `user_data` XML import | free |  shipped (reference) |
| **pfSense** | CARP | same XML import (FreeBSD sibling) | free |  **next add-on** (planned) |
| **FortiGate** | FGCP + IPAM failover fn | cloud-init bootstrap (FortiOS) - not native | VM license/trial required |  planned |
| **Palo Alto** | active/passive | PAN-OS bootstrap package (`init-cfg.txt`) - not native | VM-Series license required |  planned |
| StormShield | SNS HA | TBD | TBD |  backburner |

pfSense is first because it reuses almost all the OPNsense machinery (XML,
CARP, `user_data` import, FreeBSD CLI - `pfctl`/`ifconfig`/`netstat`), so it
validates the add-on model end-to-end with the least new code. FortiGate and
Palo Alto additionally need VM licenses/trials and a cloud-init/bootstrap
config-injection path, neither of which exists in the repo today.

FortiGate note: the dual-gateway contract needs one egress/hub WAN **plane**
per gateway (the stage today runs both gateways on a single PN), so a FortiGate
add-on must first add a second pair of PNs + NICs, then express failover as
dual-WAN SD-WAN in FortiOS. This is deliberately out of scope for the current
single-PN dual-PGW change (no unused resources pre-created - see the roadmap).

## Adding a provider - acceptance checklist

1. `firewall_provider` accepts the value; the guard passes; `vendor` reaches
   the module.
2. Golden QCOW2 imported via `firewall_image_1/2` (documented `source_url`,
   `version`, `object_key`).
3. Config template renders per-node with zero plan-time `file()` deps (content
   via `fw_passive/active_config_xml` style locals).
4. HA verified: a forced failover moves the floating VIP and mgmt stays up at
   the door.
5. Door port map verified (WebUI HTTP 200, SSH banner) for every mapped port.
6. Data plane verified: spoke egress + FW-own egress at the egress PGW IP,
   east-west direct via the hub, spokes 0% loss.
7. `providers/<vendor>/test-<vendor>.sh` passes 100% (mirrors
   the reference `providers/opnsense/test-firewalls.sh` structure, vendor-native
   commands).
8. `terraform.tfvars.sample` and docs updated; fresh `plan` = No changes on a
   rebuild.

## Layout

```
scw-lz/stages/3-security-appliances/
  main.tf / variables.tf / outputs.tf     # provider-agnostic stage core
  PROVIDERS.md                            # this file
  providers/
    opnsense/                             # reference implementation (shipped)
      opnsense-config.xml.tftpl           #   reference provider config
      test-firewalls.sh                   #   reference provider test battery
      probe-fw-passive.sh / probe-fw-active.sh  #   ad-hoc FW probing helpers
      opnsense-central-fw.qcow2           #   golden image (RELEASE, not git)
      README.md                           #   reference implementation pointers
    pfsense/README.md                     # planned add-on (next)
    fortinet/README.md                    # planned add-on
    paloalto/README.md                    # planned add-on
```
