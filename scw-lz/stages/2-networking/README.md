# Stage 2 - Networking

Deploys the hub-and-spoke network: hub + spoke VPCs, private networks,
peerings, routes, optional ACLs, public gateways, and DNS.

## What to edit

- **`envs/<env>/data/networking-<env>.yaml`**: everything this stage creates
  (VPCs, private networks, peerings, routes, VPN settings for Stage 6, ...).
- **`envs/<env>/2-networking-<env>.tfvars`**: org ID, region, zone, project.

The YAML is loaded with `yamldecode()` and turned into resources with
`for_each`. You can override any resource by defining the same key in tfvars
(the tfvars value wins via `merge()`), without touching the shared YAML.

## Usage

```bash
make apply STAGE=2 [ENV=<env>]     # or: terraform init/plan/apply in this dir
```

## Resource map

| YAML section | Module | Creates |
|---|---|---|
| `vpcs` | `modules/vpc` | Hub + spoke VPCs with private networks |
| `vpc_peerings` | `modules/vpc-peering` | Peerings between VPCs |
| `vpc_routes` | `modules/vpc-route` | Static routes for transit |
| `vpc_acls` | `modules/vpc-acl` | Traffic filtering between VPCs |
| `public_gateways` | `modules/public-gateway` | NAT/egress + bastion gateways |
| `dns_zones` / `dns_records` | `modules/dns` | DNS zones and records |

Site-to-Site VPN lives in Stage 6 (it reuses this stage's `networking.yaml`).
