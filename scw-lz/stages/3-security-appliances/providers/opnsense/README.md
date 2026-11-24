# Provider add-on - OPNsense (reference)

Status: SHIPPED / reference implementation. This is the baseline every other
provider add-on is modeled on.

The OPNsense add-on is the current stage itself:

| Piece | Location |
|---|---|
| Config template | `opnsense-config.xml.tftpl` (rendered in `../../main.tf`, passed via `fw_passive_config_xml`/`fw_active_config_xml`) |
| HA | CARP (vhid 10 LAN / vhid 11 egress), IPAM VIPs, pfsync + XMLRPC over the sync VPC |
| Config injection | OPNsense native `user_data["opnsense_config"]` import + reboot |
| Door map | WebUI `:8443` (VIP) / `:8444` `:8445` | SSH `:8022` (fw-passive) / `:8023` (fw-active) |
| Test battery | `test-firewalls.sh` (41 checks, `pfctl`/`ifconfig`/`netstat`) |
| Probe helpers | `probe-fw-passive.sh` / `probe-fw-active.sh` (ad-hoc FW state, via `scripts/lib/fw_lib.sh`) |
| Golden image | `opnsense-central-fw.qcow2` - public download: `https://ldz-fw-images.s3.fr-par.scw.cloud/Opnsense/26.1/opnsense-central-fw.qcow2` (never in git; see README "Deploy-from-golden") |
| Module | `modules/firewall` with `vendor = "opnsense"` |

## Golden image delivery

The 2.2 GB qcow2 is never in git - it ships from the public Object Storage
URL above and the stage's upload-wait gate fetches it **automatically** at
apply time (priority: local bundled file > `source_url` > manual UPLOAD
REQUIRED). No manual download step for users. See `../../README.md`
"Deploy-from-golden" for the full flow.

## Reusing this for another vendor

For **pfSense**, everything above transfers almost 1:1 (same XML schema,
CARP, native config import, FreeBSD CLI). Copy this add-on's template and test
battery, adjust the schema quirks, and follow `../../PROVIDERS.md` acceptance
checklist items 3-8.
