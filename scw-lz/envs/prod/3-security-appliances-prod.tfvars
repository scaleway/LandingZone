# ===========================================================================
# Stage 3 - Security Appliances (HA OPNsense): committed template, sanitized.
# Design data (zones, IPAM, image import, test instances) lives in
# data/security-appliances-<env>.yaml. Fill in the values below, then copy to
# 3-security-appliances-<env>-demo.tfvars (gitignored) for the live config.
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID" # Scaleway Organization ID
project_key     = "prod"        # bootstrap project hosting the firewalls
region          = "fr-par"
zone            = "fr-par-2"

# REQUIRED: same per-user prefix as the bootstrap stage (0-org-setup-<env>.tfvars)
# - in this stage it only drives the image-import bucket name
# (<prefix>-<env>-image-import-<timestamp>; the timestamp comes from the
# bootstrap output automatically).
state_bucket_prefix = "lz-myorg"

# State access comes from the bootstrap-generated remote_state-<env>.tfvars.

# OPNsense secrets - generate a bcrypt hash for the chosen root password:
#   htpasswd -bnBC 12 "" '<password>' | tr -d ':\n'
opnsense_root_password      = "lzscalewayfw" # Temporary password, please customise it for better security
opnsense_root_password_hash = "$2y$12$IbRoma62wZ4Yth7j0NqP/e2ZMjiG5XA.89C0GlmY6BRmEN0muS9NC"
carp_password               = "4qbIHOzwqWincxyE"

# SSH keys are AUTOMATED - leave unset (""):
#   - admin key comes from bootstrap's live admin_key
#   - backup exporter key comes from scw-lz/keys-prod/fw-backup/id_ed25519.pub
opnsense_ssh_public_key        = ""
opnsense_backup_ssh_public_key = ""

# S3 upload credentials - only needed when a firewall_image in the YAML has
# enable_upload: true (the default source_url flow does not need them).
upload_access_key = ""
upload_secret_key = ""
