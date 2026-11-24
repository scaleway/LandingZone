# OPNsense on Scaleway: Deployment & Configuration Cookbook

How the HA OPNsense firewall pair is deployed and configured in this toolkit - and how to customize it.

> **TL;DR** - nothing is configured by hand anymore. The whole flow is declarative:
> config XML is rendered from templates, then imported by OPNsense itself on first
> boot (`user_data["opnsense_config"]`). Edit templates or stage-3 variables,
> then `make apply STAGE=3 ENV=<env>`.

---

## 1. Architecture recap (what stage-3 deploys)

Two private-only OPNsense instances acting as the hub firewall, managed exclusively through a public-gateway **door**:

| Node | Zone | LAN | Egress | Sync | Role |
|---|---|---|---|---|---|
| `fw-passive` | `fr-par-1` | `10.10.0.11` | `10.4.0.11` | `10.255.0.11` | CARP STANDBY |
| `fw-active` | `fr-par-2` | `10.10.0.12` | `10.4.0.12` | `10.255.0.12` | CARP MASTER |

- **CARP VIPs** (floating, owned by whichever node is active): LAN `10.10.0.10` (vhid 10), egress `10.4.0.10` (vhid 11). VPC routes point at the VIPs, so either node can own them at runtime.
- **Sync plane**: `10.255.0.0/24` for pfsync + XMLRPC (state + config HA).
- **Access**: hub door PGW PAT => `8444`/`8445` (WebUI, fw-passive/fw-active), `8022`/`8023` (SSH). The firewalls have **no public IP**.

Exact IPs come from the stage-3 IP plan (`scw-lz/stages/3-security-appliances/`). If they drift, the config renders what the plan says.

---

## 2. The golden image (QCOW2 => bootable volume)

The `firewall-image` module automates the whole import:

1. Place your OPNsense QCOW2 (e.g. `OPNsense-26.1-serial-amd64.qcow2`) in the **image-import bucket** (stage-3).
2. The stage destroys/downloads nothing manually: the pipeline imports `qcow2 => SBS snapshot => SBS volume`, **one chain per firewall node + zone**.
3. Each firewall instance boots from its own SBS volume (`root_volume` of `sbs_volume` type - `PRO2-*`/`DEV1-*` instances do not boot from local SSD).

> Historical pitfalls already fixed in code: pre-signed-URL query strings no longer end up in local filenames (basename is stripped of `?`), and the boot volume is an SBS volume, not an `l_ssd`.

---

## 3. The configuration templates

OPNsense config is injected as **XML** (the native `config.xml` import), not via console keystrokes.

| File | Purpose |
|---|---|
| `modules/firewall/config/opnsense/templates/vpc-hub-spoke-fw.xml` | **Sanitized, reusable base template** for a hub-and-spoke firewall (LAN/WAN/gateways/spoke routes/rule patterns). Edit this, not the generated files. |
| `modules/firewall/config/opnsense/fw_passive.xml` / `fw_active.xml` | Node-specific references (history; the live render is stage-3's tftpl). |
| `scw-lz/stages/3-security-appliances/providers/opnsense/opnsense-config.xml.tftpl` | **The renderer**: one XML per HA node, with `hostname`, LAN/egress/sync IPs, CARP VIPs/vhids, spoke routes, and management (SSH key-only on LAN) substituted from the stage-3 IP plan. |

Key knobs exposed by stage-3 (`variables.tf`): `opnsense_root_password` (root password set on first import), the admin/backup SSH public keys, and the per-node XML from `user_data["opnsense_config"]`.

---

## 4. Deploy

```bash
make plan STAGE=3 ENV=dev      # always dry-run first
make apply STAGE=3 ENV=dev
```

What happens:

1. Golden-image volumes are imported per node/zone.
2. Stage-3 renders the OPNsense XML twice (once per HA node) from `opnsense-config.xml.tftpl`.
3. `modules/firewall` injects each XML via `user_data["opnsense_config"]`; OPNsense **imports it natively on first boot**, then reboots.
4. CARP comes up: the MASTER (`fw-active`) owns the VIPs; `fw-passive` stays STANDBY. VPC routes (already pointing at the VIPs) become live through whichever node is active.

> Manual console setup is **not** needed: interfaces, IPs, routes and rules all come from the injected config. If you ever need to touch the console, root/opnsense access goes through the hub door (see next section).

---

## 5. Access (hub door)

The firewalls are private-only; everything reaches them through the hub door PGW PAT:

| Port (public) | Target | Service |
|---|---|---|
| `8444` / `8445` | fw-passive / fw-active | OPNsense WebUI (HTTPS) |
| `8022` / `8023` | fw-passive / fw-active | SSH (key-only, LAN) |

SSH is key-only on the LAN interface - no password auth, enforced by the rendered config.

---

## 6. Customizing OPNsense

1. **Change topology values** (spoke CIDRs, LAN ranges, gateway monitors): edit `modules/firewall/config/opnsense/templates/vpc-hub-spoke-fw.xml`, then re-apply stage-3 so the render uses them.
2. **Change per-node parameters**: the renderer substitutes `hostname`, IPs, VIPs/vhids from the stage-3 IP plan. Adjust the plan / variables, not the XML, where possible.
3. **Add rules/routes by hand**: edit the base template (keep it sanitized - no root hash, no certs), or the renderer for node-specific bits. See `modules/firewall/config/opnsense/templates/README.md` for the field-by-field guide.
4. **Set the root password**: stage-3 `opnsense_root_password` (rendered hash) is imported on first boot. A plain `CHANGE_ME` placeholder in a raw template forces a console reset instead.

---

## 7. Validation & troubleshooting

```bash
# XML well-formed (on your machine, against the rendered file)
python3 -c "import xml.etree.ElementTree as ET; ET.parse('fw-passive.xml')"

# On the firewall (via door SSH: 8022/8023)
pfctl -sr | grep -E 'vtnet0|vtnet1'            # pass rules present
netstat -rn -4 | grep -E '10\.20|10\.30|169\.254\.169\.254'   # spoke routes active
```

- **Egress path**: spoke `0/0` => hub => firewall CARP VIP => egress PGW (NAT, fixed public IP). A failing hop usually shows up as a missing route on the active node or the egress gateway.
- **HA state**: expect `fw-active` to hold the CARP VIPs. If `fw-passive` took over (CARP preempt), check the sync plane (`10.255.0.0/24` pfsync/XMLRPC) and that both nodes agree on vhid/advskew.
- **Recovery**: re-apply stage-3 to re-render/re-inject the config, or reboot a node to re-import its XML.

---

## 8. Template maintenance

When you improve the **live** `fw-passive` config (add aliases, WAN port rules, ...), refresh the sanitized template from the running firewall:

```bash
# 1. download the live config
scp -i <key> root@<fw-passive-lan-ip>:/conf/config.xml tmp/fw-passive_config_downloaded.xml

# 2. rebuild the sanitized template (strips secrets + revision metadata)
python3 tmp/build_fw_template.py
```

Always keep templates sanitized: no real root password hash, no autogenerated TLS cert/private key.
