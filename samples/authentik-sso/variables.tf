variable "organization_id" {
  description = "Scaleway Organization ID (the org the bootstrap SAML/SCIM config belongs to)."
  type        = string
}

variable "project_id" {
  description = "Scaleway project ID to deploy into (default: org default project)."
  type        = string
  default     = null
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

variable "name_prefix" {
  description = "Resource name prefix (instance + security group)."
  type        = string
  default     = "lz-authentik-sso"
}

variable "environment" {
  description = "Environment label for resource tags (env:<value>). Free-form; e.g. dev/prod/sandbox."
  type        = string
  default     = "sample"
}

variable "instance_type" {
  description = "Instance commercial type. DEV1-S (2 vCPU / 2 GB) is the Authentik minimum; use PRO2-XXS/L for production."
  type        = string
  default     = "DEV1-S"
}

variable "image" {
  description = "Base image label (Ubuntu with cloud-init)."
  type        = string
  default     = "ubuntu-noble"
}

variable "root_volume_size_gb" {
  description = "Root volume size; Authentik media + container images need headroom."
  type        = number
  default     = 50
}

variable "enable_public_ip" {
  description = "Attach a flexible public IPv4 (Authentik must be reachable by end-user browsers for SAML)."
  type        = bool
  default     = true
}

variable "allowed_cidrs" {
  description = "CIDRs allowed on HTTPS/HTTP (Authentik WebUI + SAML endpoints). Public-by-design for an IdP: end-user browsers must reach the SAML login, so 0.0.0.0/0 is legitimate here. Restrict to office/IPSec CIDRs when the IdP is internal-only."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_cidrs" {
  description = "CIDRs allowed on SSH (instance admin). MANAGEMENT PLANE: never leave 0.0.0.0/0 - pin your operator /32 or an office/network range instead (open SSH gets scanned within minutes)."
  type        = list(string)
  default     = ["198.51.100.10/32"]
}

variable "authentik_fqdn" {
  description = "Public FQDN users will reach the IdP on (point DNS at the instance IP, or use the IP directly for testing)."
  type        = string
  default     = "auth.example.com"
}

variable "authentik_image_tag" {
  description = "goauthentik/server image tag (pin a stable release, e.g. 2026.8.3)."
  type        = string
  default     = "2026.8.3"
}

variable "bootstrap_email" {
  description = "Initial admin (akadmin) account email."
  type        = string
  default     = "admin@example.com"
}

variable "application_slug" {
  description = "Authentik application slug for the Scaleway console SSO app (becomes part of the IdP EntityID/SSO URL)."
  type        = string
  default     = "scaleway"
}

variable "sp_entity_id" {
  description = "Scaleway SAML Service Provider Entity ID (bootstrap output `sso.<key>.sp_entity_id`). Used by the manual/scripted IdP registration step."
  type        = string
  default     = null
}

variable "sp_acs_url" {
  description = "Scaleway SAML Assertion Consumer Service URL (bootstrap output `sso.<key>.acs_url`). Used by the manual/scripted IdP registration step."
  type        = string
  default     = null
}
