# ===========================================================================
# Stage 4 - Project Factory (committed template, sanitized - no real values).
# Resource definitions (projects, SAs, IAM, peerings, buckets) live in
# data/projects-<env>.yaml. Fill in the values below, then copy to
# 4-project-factory-<env>-demo.tfvars (gitignored) for the live config.
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags        = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id    = "YOUR_ORG_ID" # Scaleway Organization ID
parent_project_key = "prod"        # bootstrap project the factory projects attach to
region             = "fr-par"
zone               = "fr-par-2"

# State access comes from the bootstrap-generated remote_state-<env>.tfvars.
