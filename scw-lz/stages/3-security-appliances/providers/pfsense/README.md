# Provider add-on - pfSense (planned, next)

Status: PLANNED - the first add-on to build. pfSense is the fastest way
to prove the multi-vendor model because it is OPNsense's FreeBSD sibling:

- same **CARP HA** (vhid groups + IPAM virtual IPs) - the module's `is_carp`
  path already covers `vendor = "pfsense"`
- same **native config import** via `user_data["opnsense_config"]` (both use
  the OPNsense-style config.xml import)
- same **CLI surface** (`pfctl`, `ifconfig`, `netstat`) - the reference test
  battery transfers almost unchanged

## What this add-on must deliver (PROVIDERS.md checklist)

1. `firewall_provider = "pfsense"` - already accepted by the variable
   validation; remove the stage guard for it.
2. **Config template** `providers/pfsense/pfsense-config.xml.tftpl` - fork of
   `../opnsense/opnsense-config.xml.tftpl` adjusted for pfSense schema differences
   (pfSense uses the same OPNsense-style XML: system/gateways/static
   routes/aliases/manual NAT/filter). Key items to port verbatim (they are
   proven behaviors, not OPNsense-specific):
   - `ipaddr=none` on vtnet0 (WAN) - never DHCP (stale lease regression)
   - gateway **ordering** (last gateway entry = default) and
     `EGRESS_PGW_ACTIVE` default + per-`management_cidrs` `HUB_PGW_ACTIVE` reply
     routes
   - CARP vhids 10/11 with pinned advskew (fw-active master) + XMLRPC sync
   - `[MGMT]`/`[EW]` alias-based rules + hybrid NAT to the egress VIP
3. **Branded golden image** via `firewall_image_1/2` (pfSense CE ISO-QCOW2 or
   prebuilt; document `source_url`/`version`/`object_key`).
4. **Test battery** `providers/pfsense/test-pfsense.sh` - fork of
   `../opnsense/test-firewalls.sh` (same structure/checks, ASCII output).
5. `providers/pfsense/README.md` (this file) - fill in the shipped status.

## Open questions

- pfSense CE vs Plus (Plus licensing); version pin.
- Whether the golden must pre-install the XML-RPC sync user like the OPNsense
  golden (`admin` + `sync` user) or whether pfSense's default admin suffices.
- WebUI default: HTTPS 443, same as OPNsense - identical door port map.
