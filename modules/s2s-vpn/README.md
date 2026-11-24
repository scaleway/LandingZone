# Scaleway Site-to-Site VPN Module

Creates and manages Scaleway Site-to-Site VPN resources for hybrid connectivity (on-premises to Scaleway). Each VPN connection entry creates four resources:

1. **VPN Gateway** -- Scaleway-side gateway attached to a Private Network
2. **Customer Gateway** -- Remote endpoint (public IP + ASN)
3. **Routing Policy** -- BGP prefix filtering (routes accepted from / advertised to peer)
4. **VPN Connection** -- IPSec tunnel with BGP routing linking the two gateways

The pre-shared key (PSK) is auto-generated and stored in Scaleway Secret Manager. Retrieve it using the `secret_ids` and `secret_versions` outputs.

## Usage

```hcl
module "s2s_vpn" {
  source = "./modules/s2s-vpn"

  region     = "fr-par"
  zone       = "fr-par-2"
  project_id = "your-project-id"

  vpn_connections = {
    on-prem-to-hub = {
      # VPN Gateway (Scaleway side)
      gateway_type       = "VGW-S"
      private_network_id = scaleway_vpc_private_network.hub_net.id

      # Customer Gateway (on-prem side)
      customer_ipv4_public = "203.0.113.1"
      customer_asn         = 65000

      # Routing Policy
      prefix_filter_in  = ["10.0.0.0/16"]   # Routes accepted from on-prem
      prefix_filter_out = ["10.10.0.0/24"]   # Routes advertised to on-prem

      # BGP tunnel IPs
      bgp_private_ip      = "169.254.0.1/30"
      bgp_peer_private_ip = "169.254.0.2/30"

      # IPSec ciphers
      ikev2_encryption = "aes256"
      ikev2_integrity  = "sha256"
      ikev2_dh_group   = "modp2048"
      esp_encryption   = "aes256"
      esp_integrity    = "sha256"
      esp_dh_group     = "modp2048"

      tags = ["hybrid", "on-prem"]
    }
  }
}
```

## Retrieving the Pre-Shared Key (PSK)

The PSK is auto-generated and stored in Secret Manager. Use a `scaleway_secret_version` data source to retrieve it:

```hcl
data "scaleway_secret_version" "s2s_psk" {
  secret_id = module.s2s_vpn.secret_ids["on-prem-to-hub"]
  revision  = tostring(module.s2s_vpn.secret_versions["on-prem-to-hub"])
}

output "psk" {
  value     = data.scaleway_secret_version.s2s_psk.data
  sensitive = true
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| region | The region for S2S VPN resources. | `string` | `"fr-par"` | no |
| zone | The zone for S2S VPN gateway placement. | `string` | `"fr-par-2"` | no |
| project_id | The Scaleway project ID. | `string` | `null` | no |
| vpn_connections | Map of S2S VPN connections to create. | `map(object)` | `{}` | no |

### `vpn_connections` object schema

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| gateway_name | Name of the VPN gateway. Auto-generated if not set. | `string` | `null` | no |
| gateway_type | VPN gateway type (commercial offer). | `string` | `"VGW-S"` | no |
| private_network_id | ID of the Private Network to attach the VPN gateway. | `string` | n/a | yes |
| ipam_ipv4_id | IPAM IPv4 ID for the VPN gateway public IP. | `string` | `null` | no |
| ipam_ipv6_id | IPAM IPv6 ID for the VPN gateway public IP. | `string` | `null` | no |
| customer_gateway_name | Name of the customer gateway. Auto-generated if not set. | `string` | `null` | no |
| customer_ipv4_public | Public IPv4 of the on-prem VPN endpoint. | `string` | n/a | yes |
| customer_ipv6_public | Public IPv6 of the on-prem VPN endpoint. | `string` | `null` | no |
| customer_asn | ASN of the customer gateway (must differ from 12876). | `number` | n/a | yes |
| routing_policy_name | Name of the routing policy. Auto-generated if not set. | `string` | `null` | no |
| prefix_filter_in | IP prefixes (CIDR) accepted from the peer. | `list(string)` | `[]` | no |
| prefix_filter_out | IP prefixes (CIDR) advertised to the peer. | `list(string)` | `[]` | no |
| connection_name | Name of the VPN connection. Auto-generated if not set. | `string` | `null` | no |
| initiation_policy | Who initiates the IPSec tunnel. | `string` | `"customer_gateway"` | no |
| enable_route_propagation | Whether route propagation is enabled. | `bool` | `true` | no |
| is_ipv6 | Whether the tunnel uses IPv6. | `bool` | `false` | no |
| bgp_private_ip | Scaleway BGP IP inside the tunnel (CIDR). | `string` | `null` | no |
| bgp_peer_private_ip | Customer BGP IP inside the tunnel (CIDR). | `string` | `null` | no |
| ikev2_encryption | IKEv2 Phase 1 encryption algorithm. | `string` | `null` | no |
| ikev2_integrity | IKEv2 Phase 1 integrity algorithm. | `string` | `"sha256"` | no |
| ikev2_dh_group | IKEv2 Phase 1 DH group. | `string` | `"modp2048"` | no |
| esp_encryption | ESP Phase 2 encryption algorithm. | `string` | `null` | no |
| esp_integrity | ESP Phase 2 integrity algorithm. | `string` | `"sha256"` | no |
| esp_dh_group | ESP Phase 2 DH group. | `string` | `"modp2048"` | no |
| tags | Tags to apply to all resources. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| vpn_gateway_ids | Map of VPN gateway IDs. |
| vpn_gateway_statuses | Map of VPN gateway statuses. |
| vpn_gateway_asns | Map of VPN gateway ASNs (Scaleway side, typically 12876). |
| customer_gateway_ids | Map of customer gateway IDs. |
| routing_policy_ids | Map of routing policy IDs (IPv4 and IPv6 combined). |
| connection_ids | Map of VPN connection IDs. |
| connection_statuses | Map of VPN connection statuses. |
| tunnel_statuses | Map of IPSec tunnel statuses. |
| bgp_statuses | Map of BGP session statuses. |
| secret_ids | Map of Secret Manager secret IDs containing the PSK. |
| secret_versions | Map of Secret Manager secret versions for the PSK. |