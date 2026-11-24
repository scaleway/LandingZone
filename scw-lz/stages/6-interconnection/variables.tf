variable "organization_id" {
  description = "Scaleway Organization ID."
  type        = string
}

# ---------------------------------------------------------------------------
# Common resource tags (var.common_tags): the org's own tagging policy, fed
# into module "common_tags" (modules/tags), which appends the toolkit-reserved
# markers managed-by / env / stage on top (single source of truth). Validation
# lives in that module too: keys/values with '=' or ':' are rejected, and the
# reserved keys cannot be set by users.
# ---------------------------------------------------------------------------

variable "common_tags" {
  description = "Org-wide resource tags (key=value) applied to every resource this stage creates, in addition to the toolkit-reserved managed-by/env/stage markers (applied by modules/tags)."
  type        = map(string)
  default     = {}
}

variable "project_key" {
  description = "Key of the project from bootstrap to deploy interconnection resources into (e.g., dev, prod)."
  type        = string
}

variable "region" {
  description = "Scaleway default region."
  type        = string
  default     = "fr-par"
}

variable "zone" {
  description = "Scaleway default zone."
  type        = string
  default     = "fr-par-2"
}

# ---------------------------------------------------------------------------
# Remote state (bootstrap + Stage 2)
# ---------------------------------------------------------------------------

variable "state_bucket" {
  description = "S3 bucket holding the Terraform remote state."
  type        = string
}

variable "state_endpoint" {
  description = "S3-compatible endpoint of the state bucket."
  type        = string
}

variable "state_access_key" {
  description = "Access key for the state bucket."
  type        = string
  sensitive   = true
}

variable "state_secret_key" {
  description = "Secret key for the state bucket."
  type        = string
  sensitive   = true
}

# ---------------------------------------------------------------------------
# Site-to-Site VPN connections (managed)
# ---------------------------------------------------------------------------

variable "s2s_vpn_connections" {
  description = <<EOF
Map of Site-to-Site VPN connections to create with the managed VPN module.
The schema extends the Stage-2 connectivity definition with `onprem_lab_peer`
(true = this connection terminates on the emulated on-premises gateway of this
stage: `customer_ipv4_public` and `ipam_ipv4_id` are then resolved from the
on-prem lab instead of static values).

Other fields (vpc_key / private_network_key) resolve the hub Private Network
through Stage-2's remote state.
EOF
  type = map(object({
    # VPN Gateway (Scaleway side)
    gateway_name        = optional(string)
    gateway_type        = optional(string, "VGW-S")
    vpc_key             = string
    private_network_key = string
    ipam_ipv4_id        = optional(string)
    ipam_ipv6_id        = optional(string)

    # Customer Gateway (on-prem side)
    customer_gateway_name = optional(string)
    customer_ipv4_public  = optional(string)
    customer_ipv6_public  = optional(string)
    customer_asn          = optional(number)

    # Routing Policy
    routing_policy_name = optional(string)
    prefix_filter_in    = optional(list(string), [])
    prefix_filter_out   = optional(list(string), [])

    # Connection
    connection_name          = optional(string)
    initiation_policy        = optional(string, "customer_gateway")
    enable_route_propagation = optional(bool, true)
    is_ipv6                  = optional(bool, false)

    # BGP tunnel IPs
    bgp_private_ip      = optional(string)
    bgp_peer_private_ip = optional(string)

    # IPSec ciphers (optional, Scaleway applies defaults if not set)
    ikev2_encryption = optional(string)
    ikev2_integrity  = optional(string)
    ikev2_dh_group   = optional(string)
    esp_encryption   = optional(string)
    esp_integrity    = optional(string)
    esp_dh_group     = optional(string)

    # PSK, pre-shared key for the tunnel (optional). When omitted the module
    # generates one and stores it in a terraform-owned Secret Manager secret.
    psk = optional(string)

    # Lab wiring
    onprem_lab_peer = optional(bool, false)

    tags = optional(list(string), [])
  }))
  default = {}
}

variable "stage0_state_path" {
  description = "Path (relative to this stage dir) of the bootstrap LOCAL state file - source of project_ids, ssh_public_keys, environment. Written by bootstrap into remote_state-<env>.tfvars."
  type        = string
}
