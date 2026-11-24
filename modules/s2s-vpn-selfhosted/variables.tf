variable "name" {
  description = "Short name of the gateway (used for resource naming: lz-<env>-<name>[-sg])."
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)."
  type        = string
}

variable "project_id" {
  description = "The Scaleway project ID."
  type        = string
  default     = null
}

variable "zone" {
  description = "The zone for the gateway instance."
  type        = string
  default     = "fr-par-2"
}

variable "instance_type" {
  description = "Commercial type of the gateway instance (e.g. PLAY2-MICRO, DEV1-S)."
  type        = string
  default     = "PLAY2-MICRO"
}

variable "image" {
  description = "UUID or label of the base image (e.g. ubuntu_jammy)."
  type        = string
  default     = "ubuntu_jammy"
}

variable "create" {
  description = "Whether to create the gateway instance (false = module computes nothing)."
  type        = bool
  default     = true
}

variable "state" {
  description = "Desired state of the gateway instance (started/stopped)."
  type        = string
  default     = "started"
}

variable "boot_type" {
  description = "Boot type of the gateway instance (local/bootscript/rescue)."
  type        = string
  default     = "local"
}

variable "tags" {
  description = "Tags to apply to the gateway resources."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Network attachment
# ---------------------------------------------------------------------------
variable "private_network_id" {
  description = "ID of the Private Network the gateway is attached to (e.g. the on-premises LAN)."
  type        = string
}

variable "private_ip" {
  description = "Static IPv4 to pin on the Private Network (IPAM reservation), or null for DHCP."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Public endpoint
# ---------------------------------------------------------------------------
variable "public_ip_id" {
  description = "ID of an existing elastic public IP to attach (stable remote endpoint). Leave null to skip."
  type        = string
  default     = null
}

variable "public_ip" {
  description = "Public IPv4 address of this gateway (used as the IKE local identity + VTI local)."
  type        = string
}

variable "remote_public_ip" {
  description = "Public IPv4 address of the remote VPN endpoint (the managed VPN gateway)."
  type        = string
}

# ---------------------------------------------------------------------------
# Tunnel (BGP over IPSec) parameters
# ---------------------------------------------------------------------------
variable "local_tunnel_ip" {
  description = "Tunnel IPv4 of THIS side, in CIDR form (e.g. 169.254.0.2/30). Placed on the vti interface."
  type        = string
}

variable "remote_tunnel_ip" {
  description = "Tunnel IPv4 of the peer (the /30 gateway), without mask (e.g. 169.254.0.1)."
  type        = string
}

variable "local_bgp_ip" {
  description = "Tunnel IPv4 of THIS side used by BGP, without mask (e.g. 169.254.0.2). Same address as local_tunnel_ip minus the /30."
  type        = string
}

variable "local_asn" {
  description = "ASN of this side (must differ from the remote side)."
  type        = number
}

variable "remote_asn" {
  description = "ASN of the remote side (the managed VPN gateway, typically 12876)."
  type        = number
}

variable "psk" {
  description = "Pre-shared key for the IKEv2 connection (sensitive). Must match the remote side."
  type        = string
  sensitive   = true
}

variable "ike_ciphers" {
  description = "IKEv2 Phase-1 cipher suite (strongSwan syntax, e.g. aes256-sha256-modp2048)."
  type        = string
  default     = "aes256-sha256-modp2048"
}

variable "esp_ciphers" {
  description = "ESP Phase-2 cipher suite (strongSwan syntax, e.g. aes256-sha256-modp2048)."
  type        = string
  default     = "aes256-sha256-modp2048"
}

variable "advertise_cidrs" {
  description = "CIDRs advertised over BGP to the remote side (this site's networks)."
  type        = list(string)
  default     = []
}

variable "learn_cidrs" {
  description = "CIDRs expected from the remote side over BGP (documentation only; BGP installs what is received)."
  type        = list(string)
  default     = []
}

variable "tunnel_interface" {
  description = "Name of the VTI interface encapsulating the tunnel."
  type        = string
  default     = "vti0"
}

variable "router_id" {
  description = "BGP router ID (typically the Private Network IPv4 of the gateway)."
  type        = string
  default     = null
}

variable "ssh_cidrs" {
  description = "Source CIDRs allowed to SSH to the gateway (operator access)."
  type        = list(string)
  default     = []
}

variable "ssh_keys" {
  description = "SSH public keys granted operator access to the gateway (e.g. an ops team bastion key). Empty = no key provisioning."
  type        = list(string)
  default     = []
}
