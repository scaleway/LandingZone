# Scaleway Self-Hosted Site-to-Site VPN Module

The **self-hosted counterpart** to [`modules/s2s-vpn`](../s2s-vpn) (Scaleway's managed VPN service). It provisions a compute instance that acts as a VPN gateway at a remote site: the classic **customer-gateway** role: using:

| Layer | Technology | Role |
|---|---|---|
| Tunnel | **strongSwan** (IKEv2 / IPSec) | Encrypted site-to-site tunnel |
| Routing | **BIRD2** (BGP) | Route exchange with the peer over the tunnel |
| Data plane | mark/VTI (`vti0`) | Carries BGP + payload inside the tunnel |

A typical deployment (see stage `6-interconnection`) pairs this module with the managed `modules/s2s-vpn` module: the managed gateway lives on the Scaleway hub Private Network, and *this* module emulates: or actually runs: the on-premises gateway that dials it. BGP does the real routing (no static encapsulation routes): this side advertises its site networks and learns the remote CIDRs through `enable_route_propagation`.

## Bootstrapping model

The instance is provisioned **after** the managed connection exists (stage 6 wires `depends_on` through a Secret Manager read), so cloud-init carries:

- the **PSK** of the auto-generated managed connection secret,
- the **remote public IP** of the managed VPN gateway (a zonal public IPAM reservation),
- the **remote ASN** (12876) and the /30 **BGP tunnel IPs**.

That keeps the whole bring-up declarative: no post-apply remote-exec step.

## Usage

```hcl
module "onprem_gateway" {
  source = "./modules/s2s-vpn-selfhosted"

  name          = "onprem-gw"
  environment   = "dev"
  project_id    = "your-project-id"
  zone          = "fr-par-2"

  # Network
  private_network_id = scaleway_vpc_private_network.onprem_net.id
  private_ip         = "10.40.0.10"

  # Public endpoint (this side + the managed VPN's customer gateway)
  public_ip_id        = scaleway_instance_ip.onprem_pub.id
  public_ip           = scaleway_instance_ip.onprem_pub.address
  remote_public_ip    = scaleway_ipam_ip.vgw_public.address

  # Tunnel
  local_tunnel_ip  = "169.254.0.2/30"
  local_bgp_ip     = "169.254.0.2"
  remote_tunnel_ip = "169.254.0.1"
  local_asn        = 65000
  remote_asn       = 12876
  # The managed connection's secret returns the PSK as *raw base64*; both
  # gateways expect the decoded string, so base64decode() it (see stage 6).
  psk              = base64decode(data.scaleway_secret_version.s2s_psk.data)

  advertise_cidrs = ["10.40.0.0/24"]  # this site's networks
  learn_cidrs     = ["10.10.0.0/24", "10.20.0.0/24", "10.30.0.0/24"]

  ssh_cidrs = ["88.172.185.2/32"]     # SG rule: who may reach port 22
  ssh_keys  = ["ssh-ed25519 AAAA... lzops@ops"]  # optional operator keys
}
```

## How routes are announced

BIRD peers with the managed gateway over the tunnel (BGP on the VTI), but the site prefixes it advertises are *not* pulled from the kernel: Linux marks a directly-connected route as `proto kernel`, which BIRD2 does not import. The module therefore announces `advertise_cidrs` through a **static blackhole route**:

- `protocol static lz_lan` injects `route <cidr> blackhole;`: a pure announcement, no forwarding intent;
- the kernel protocol's export filter drops blackhole/unreachable/prohibit routes (`if dest ~ [ RTD_BLACKHOLE, RTD_UNREACHABLE, RTD_PROHIBIT ] then reject`), so BIRD never re-installs them over the real route;
- actual forwarding stays on the kernel's directly-connected route (`<cidr> dev <nic> proto kernel scope link`).

`learn_cidrs` (the remote/cloud prefixes) arrive over BGP as usual with `import all` and are installed into the kernel; each is also listed in cloud-init as an idempotent safety-net route (`ip route add ... || true`) so traffic survives the few seconds while BGP converges after boot.

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Short gateway name (resource prefix `lz-<env>-<name>`). | `string` | n/a | yes |
| environment | Environment name (dev/prod). | `string` | n/a | yes |
| project_id | Scaleway project ID. | `string` | `null` | no |
| zone | Zone for the instance. | `string` | `"fr-par-2"` | no |
| instance_type | Instance commercial type. | `string` | `"PLAY2-MICRO"` | no |
| image | Base image label/UUID. | `string` | `"ubuntu_jammy"` | no |
| create | Whether to create the instance. | `bool` | `true` | no |
| state | Desired instance state. | `string` | `"started"` | no |
| private_network_id | PN to attach the gateway to (the site LAN). | `string` | n/a | yes |
| private_ip | Static IPv4 pinned on the PN (IPAM). | `string` | `null` | no |
| public_ip_id | Existing elastic public IP id to attach. | `string` | `null` | no |
| public_ip | Public IPv4 of this gateway (IKE local identity). | `string` | n/a | yes |
| remote_public_ip | Public IPv4 of the peer (managed VPN gateway). | `string` | n/a | yes |
| local_tunnel_ip | This side's /30 tunnel IPv4 (CIDR). | `string` | n/a | yes |
| local_bgp_ip | Same tunnel IPv4, bare (BIRD local). | `string` | n/a | yes |
| remote_tunnel_ip | Peer /30 address (BIRD neighbor, no mask). | `string` | n/a | yes |
| local_asn | This side ASN (!= remote). | `number` | n/a | yes |
| remote_asn | Peer ASN (Scaleway typically 12876). | `number` | n/a | yes |
| psk | Pre-shared key (sensitive), must match the managed connection. Sourced from a `scaleway_secret_version` the value is raw base64: `base64decode()` it first. | `string` | n/a | yes |
| ike_ciphers | IKEv2 Phase-1 suite. | `string` | `"aes256-sha256-modp2048"` | no |
| esp_ciphers | ESP Phase-2 suite. | `string` | `"aes256-sha256-modp2048"` | no |
| advertise_cidrs | CIDRs this site advertises over BGP. | `list(string)` | `[]` | no |
| learn_cidrs | CIDRs expected from the peer (safety-net routes). | `list(string)` | `[]` | no |
| tunnel_interface | VTI interface name. | `string` | `"vti0"` | no |
| router_id | BGP router ID (defaults to the pinned private IP). | `string` | `null` | no |
| ssh_cidrs | Source CIDRs allowed for SSH access. | `list(string)` | `[]` | no |
| ssh_keys | SSH public keys injected for operator access (cloud-init `users` block). Empty = none. | `list(string)` | `[]` | no |
| tags | Tags for all created resources. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | Instance ID. |
| name | Instance name. |
| private_ips | Private IPs of the gateway. |
| private_ips_map | Private IPs keyed by PN key. |
| public_ip_id | Attached elastic public IP ID. |
| private_nic_ids | Private-NIC IDs keyed by PN key (VPC route next hops). |

## Security

- The security group only exposes **UDP 500/4500** (IPSec) and optional SSH.
- The PSK travels inside instance `user_data` (visible to instance metadata holders): appropriate for a lab/reference; production sites would fetch the secret on the box instead.
