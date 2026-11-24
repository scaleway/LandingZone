# Provider add-on - FortiGate (planned)

Status: PLANNED. FortiGate VM on KVM/QEMU shape with **FGCP HA**
(active/passive or active-active), dual-WAN capable. `modules/firewall` already
has vendor scaffolding for FortiGate (dual-WAN NICs, cloud-init config drop,
and an **IPAM failover function** in `failover.tf`).

## Hard parts (why it is not a copy of OPNsense)

1. **Config injection is not native.** FortiOS does not import a config from
   metadata the way OPNsense does. The module's current approach drops a
   `fortigate/primary.conf` `secondary.conf` bundle via cloud-init
   `write_files` to `/etc/fortigate/config-backup` - needs a real verification
   and likely a bootstrap mechanism (FortiGate accepts `fortios.conf` on a
   config-drive or via `exec restore config` after first boot).
2. **Licensing.** Full throughput + advanced features need a FortiGate VM
   license (or a 15-day trial) registered per appliance - a per-instance
   concern the stage must surface in tfvars/docs.
3. **HA semantics.** FGCP keeps its own virtual cluster address; the module's
   `is_carp = false` path + IPAM failover function is the intended mechanism -
   the hub steering target (the floating FW address that the `0.0.0.0/0 -> FW`
   route points at) must match whatever the FGCP cluster owns.

## Deliverables (PROVIDERS.md checklist)

- Config template `providers/fortinet/fortigate.conf.tftpl` (per-node: hostname,
  interfaces vtnet0-vtnet3 mapping, gateways 10.10.0.2/10.4.0.2, management
  ACL, NAT/route for spoke egress via egress VIP).
- Licensing + first-boot bootstrap documented (source URL for the golden,
  license file placement).
- Door map: WebUI HTTPS `:443`, SSH `:22` - same PAT ports as OPNsense.
- Test battery `providers/fortinet/test-fortinet.sh` with vendor CLI:
  `get system status`, `get system ha status`, `get system interface physical`,
  `get router info routing-table all`, `diagnose sniffer packet any`.
- `firewall_provider = "fortigate"` unguarded.

## Open questions

- License model for the deployment (per-pair license vs trial).
- FGCP heartbeat interface: reuse the sync VPC (`10.255.0.0/24`).
