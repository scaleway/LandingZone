# ===========================================================================
# Stage 2 - Networking: Terraform Variables
# Resource definitions (VPCs, peerings, routes, ACLs, VPN, gateways, DNS,
# firewall appliances, load balancers) live in: data/networking.yaml
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
project_key = "dev"

# State access is NOT configured here: state_bucket / state_endpoint /
# state_access_key / state_secret_key come from the bootstrap-generated
# remote_state-<env>.tfvars (run_stage passes it AFTER this file - the last
# -var-file wins). The stage's own state backend comes from backend-<env>.tfvars.