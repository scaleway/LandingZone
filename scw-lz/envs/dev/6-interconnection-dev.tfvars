# ===========================================================================
# Stage 6 - Interconnection: live terraform.tfvars (local, gitignored)
# Resource definitions live in: data/interconnection.yaml
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID" # Scaleway Organization ID
project_key     = "dev"         # bootstrap project hosting the interconnection
region          = "fr-par"
zone            = "fr-par-2"

# State access comes from the bootstrap-generated remote_state-<env>.tfvars
# (run_stage passes it after this file; the last -var-file wins).
