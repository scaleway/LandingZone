# ===========================================================================
# Bootstrap - Organization Setup (committed template, sanitized - no real values).
# Resource definitions (projects, IAM, SSH keys, KMS, audit, secrets) live in
# data/org-<env>.yaml. Fill in the values below, then copy to
# 0-org-setup-<env>-demo.tfvars (gitignored) for the live config.
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}                # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID"     # Scaleway Organization ID (required)
project_id      = "YOUR_PROJECT_ID" # Project that hosts the org-layer resources
region          = "fr-par"
zone            = "fr-par-2"
environment     = "prod" # env name: dev | prod

# Project names get this prefix: <project_prefix>-<env> and
# <project_prefix>-<env>-infra-ops. Default 'lz' keeps lz-dev / lz-dev-infra-ops;
# set your own (e.g. company acronym) before the FIRST bootstrap, changing it
# later would recreate the projects.
project_prefix = "lz"

# REQUIRED: unique per-user prefix for all bootstrap-named buckets (state,
# audit, image-import, backup/DR) - bucket names are globally unique on
# Scaleway. A frozen creation timestamp is appended automatically, so names
# become <prefix>-<env>-<purpose>-<timestamp> (e.g. lz-myorg-prod-backup-dr-20261113t091500z; lowercased for S3).
state_bucket_prefix = "lz-myorg"

# Per-env SSH keypair directory (relative to the bootstrap dir, so
# ../keys-prod -> scw-lz/keys-prod). Required by bootstrap for IAM SSH keys and
# by test-firewalls.sh for the matching ENV. dev uses keys-dev, prod keys-prod.
ssh_key_dir = "../keys-prod"
