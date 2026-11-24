# ===========================================================================
# Stage 2 - Networking (committed template, sanitized - no real values).
# Resource definitions (VPCs, peerings, routes, VPN, gateways, DNS) live in
# data/networking-<env>.yaml. Fill in the values below, then copy to
# 2-networking-<env>-demo.tfvars (gitignored) for the live config.
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID" # Scaleway Organization ID
region          = "fr-par"
zone            = "fr-par-2"

# Which project from bootstrap to deploy networking resources into (ID resolved
# via terraform_remote_state).
project_key = "prod"

# State access comes from the bootstrap-generated remote_state-<env>.tfvars.
