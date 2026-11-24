# ===========================================================================
# Stage 6 - Interconnection (committed template, sanitized - no real values).
# Resource definitions (S2S VPN, on-prem lab) live in
# data/networking-<env>.yaml. Fill in the values below, then copy to
# 6-interconnection-<env>-demo.tfvars (gitignored) for the live config.
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID" # Scaleway Organization ID
project_key     = "prod"        # bootstrap project hosting the interconnection
region          = "fr-par"
zone            = "fr-par-2"

# State access comes from the bootstrap-generated remote_state-<env>.tfvars.
