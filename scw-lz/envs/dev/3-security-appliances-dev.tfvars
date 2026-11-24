# ===========================================================================
# Stage 3 - Security Appliances: live terraform.tfvars
# ===========================================================================

# ---------------------------------------------------------------------------
# Common resource tags - applied to EVERY resource this stage creates, on top
# of the toolkit-reserved markers (managed-by / env / stage). Plan your org
# tags here (team, costcenter, owner, ...); repeat the same block in every
# stage tfvars you use, or leave {} to rely on the reserved markers only.
# ---------------------------------------------------------------------------
common_tags     = {}            # e.g. common_tags = { compliance = "pci-dss", data-classification = "internal" }
organization_id = "YOUR_ORG_ID" # Scaleway Organization ID
project_key     = "dev"         # bootstrap project hosting the firewalls
region          = "fr-par"
zone            = "fr-par-2"

# REQUIRED: same per-user prefix as the bootstrap stage (0-org-setup-<env>.tfvars)
# - in this stage it only drives the image-import bucket name
# (<prefix>-<env>-image-import-<timestamp>; the timestamp comes from the
# bootstrap output automatically).
state_bucket_prefix = "lz-myorg"

# Object storage bucket for the firewall image imports. NOTE: the default
# (lz-dev-fw-image-import, with the -fw) is stuck in Scaleway's S3 deletion GC
# from an aborted apply (BucketAlreadyOwnedByYou: currently being deleted),
# so we pin the -fw-free name here.
# HA node zones - fw-active = master (fr-par-2), fw-passive = backup (fr-par-1)

# CIDRs (hub/spokes from Stage 2, sync/egress owned by Stage 3)

# Source IPs allowed to manage the OPNsense WebUI + SSH (directly on the FW
# public IPs in flexible-IP mode). 88.172.185.2 = current operator egress.
# ---------------------------------------------------------------------------
# OPNsense secrets - never commit real values.
# Generate the bcrypt hash for a chosen root password with:
#   htpasswd -bnBC 12 "" '<password>' | tr -d ':\n'
# ---------------------------------------------------------------------------
opnsense_root_password      = "lzscalewayfw"
opnsense_root_password_hash = "$2y$12$IbRoma62wZ4Yth7j0NqP/e2ZMjiG5XA.89C0GlmY6BRmEN0muS9NC"
carp_password               = "iIyZnhy9cQyBlHlrToKIFnlB"

# SSH keys are AUTOMATED - no hand-pasted values here:
#   - root/admin key: stage-3 derives it from stage-0's live admin key
#     (ssh_public_keys["admin_key"]) - same source the test spokes use.
#   - backup exporter key: stage-3 reads scw-lz/keys-dev/fw-backup/id_ed25519.pub.
# Omit opnsense_ssh_public_key / opnsense_backup_ssh_public_key entirely.

# Firewall image import: platform-published prebuilt golden image
# (opnsense-central-fw, PNIC-aligned + UEFI/ESP-valid). The stage fetches it
# from source_url and uploads it via the upload-wait gate; enable_upload=false
# skips download/convert and the module imports per-zone SBS snapshots.

# State access comes from the bootstrap-generated remote_state-<env>.tfvars.
