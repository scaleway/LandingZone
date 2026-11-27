# Provider add-on - Palo Alto Networks (planned)

Status: PLANNED. PAN-OS (VM-Series) on KVM/QEMU with **active/passive
HA**. `modules/firewall` already has `vendor = "paloalto"` scaffolding
(cloud-init config drop of `config/paloalto/62.xml`).

## Hard parts

1. **Licensing.** VM-Series requires a license (BYOL/auth-code, or a trial) -
   per-instance, must be surfaced in tfvars/docs. Without a valid license the
   data plane is limited.
2. **Config injection is not native.** PAN-OS first-boot bootstrap is a
   **bootstrap package** (`init-cfg.txt` + XML config) placed on a small
   bootstrap partition/ISO or served over HTTP/SCP - the module's current
   cloud-init `write_files` drop needs validation against the QEMU image
   shape and likely rework into a proper bootstrap device.
3. **HA semantics.** Active/passive HA pair with a shared configuration
   context; the floating **management IP** and the dataplane addresses move on
   failover. The hub steering `0.0.0.0/0 -> FW` route must target the
   dataplane floating IP the pair owns. Module's `is_carp = false` path
   applies; an IPAM/route re-point mechanism on failover is required (see the
   provider add-on contract).
4. **Images.** VM-Series QCOW2 (PAN-OS) must be sourced/versioned per release;
   the `firewall_image_1/2` pipeline is generic and applies as-is.

## Deliverables (PROVIDERS.md checklist)

- Bootstrap bundle `providers/paloalto/` (`init-cfg.txt.tftpl` +
  `bootstrap.xml.tftpl`, per-node + HA peer), rendered per node via locals.
- Golden QCOW2 source pinned in tfvars (or bootstrap device build script).
- Door map: WebUI HTTPS `:443`, SSH `:22` - same PAT ports as OPNsense.
- Test battery `providers/paloalto/test-paloalto.sh` with PAN CLI:
  `show system info`, `show high-availability state`, `show routing route`,
  `show interface all`, `tcpdump filter` for the wire proof.
- `firewall_provider = "paloalto"` unguarded.

## Open questions

- PAN-OS version to target and license/trial availability.
- Whether active/passive failover re-points the hub steering route (static
  `scaleway_vpc_route` to the VIP) or relies on the floating IP moving.
