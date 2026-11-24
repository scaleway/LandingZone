variable "region" {
  description = "The region for S2S VPN resources."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "The zone for S2S VPN gateway placement."
  type        = string
  default     = "fr-par-2"
}

variable "project_id" {
  description = "The Scaleway project ID."
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (e.g., dev, prod). Used for default resource naming: lz-[env]-networking-vpn-[resource]-[key]."
  type        = string
  default     = "dev"
}

variable "vpn_connections" {
  description = <<EOF
Map of Site-to-Site VPN connections to create.

Each entry creates:
  - A VPN Gateway (Scaleway side, attached to a Private Network)
  - A Customer Gateway (remote endpoint public IP + ASN)
  - A Routing Policy (BGP prefix filtering)
  - A VPN Connection (IPSec tunnel with BGP)

Key fields:
  - private_network_id     (required) ID of the Private Network to attach the VPN gateway to
  - customer_ipv4_public   (required) Public IPv4 of the on-prem VPN endpoint
  - customer_asn           (required) ASN of the customer gateway (must differ from 12876)
  - prefix_filter_in       Routes accepted from the peer
  - prefix_filter_out      Routes advertised to the peer
  - bgp_private_ip         Scaleway BGP IP inside the tunnel (e.g. 169.254.0.1/30)
  - bgp_peer_private_ip    Customer BGP IP inside the tunnel (e.g. 169.254.0.2/30)
  - ikev2_encryption       IKEv2 Phase 1 encryption (e.g. aes256)
  - ikev2_integrity        IKEv2 Phase 1 integrity (default sha256)
  - ikev2_dh_group         IKEv2 Phase 1 DH group (default modp2048)
  - esp_encryption         ESP Phase 2 encryption (e.g. aes256)
  - esp_integrity          ESP Phase 2 integrity (default sha256)
  - esp_dh_group           ESP Phase 2 DH group (default modp2048)
  - psk                    PSK for the tunnel (optional; random-generated + stored in a
                           terraform-owned Secret Manager secret when omitted)
EOF
  type = map(object({
    # VPN Gateway
    gateway_name       = optional(string)
    gateway_type       = optional(string, "VGW-S")
    private_network_id = string
    ipam_ipv4_id       = optional(string)
    ipam_ipv6_id       = optional(string)

    # Customer Gateway
    customer_gateway_name = optional(string)
    customer_ipv4_public  = string
    customer_ipv6_public  = optional(string)
    customer_asn          = number

    # Routing Policy
    routing_policy_name = optional(string)
    prefix_filter_in    = optional(list(string), [])
    prefix_filter_out   = optional(list(string), [])

    # Connection
    connection_name          = optional(string)
    initiation_policy        = optional(string, "customer_gateway")
    enable_route_propagation = optional(bool, true)
    is_ipv6                  = optional(bool, false)

    # PSK, pre-shared key for the IPSec tunnel. Omitted: a random value is
    # generated and stored in a terraform-owned Secret Manager secret. Set to
    # pin a value (e.g. an operator-chosen PSK already on the on-prem device).
    psk = optional(string)

    # BGP
    bgp_private_ip      = optional(string)
    bgp_peer_private_ip = optional(string)

    # IPSec Ciphers
    ikev2_encryption = optional(string)
    ikev2_integrity  = optional(string)
    ikev2_dh_group   = optional(string)
    esp_encryption   = optional(string)
    esp_integrity    = optional(string)
    esp_dh_group     = optional(string)

    # Common
    tags = optional(list(string), [])
  }))
  default = {}
}