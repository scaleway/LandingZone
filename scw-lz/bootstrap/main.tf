/**
 * Bootstrap Stage, day-0 org + infra-ops setup. One stage = one key = one project.
 *
 * Creates:
 *   - infra-ops project + terraform-state bucket (local state; the seed)
 *   - bootstrap SA/key (default project = infra-ops) + org-wide IAM policies
 *   - the lz-<env> project, the lz deploy SA/key (default project = lz-<env>)
 *   - org IAM groups, service accounts, SSH keys, KMS, audit buckets, secrets,
 *     and optional SSO (SAML/SCIM)
 *   - per-env config for the other stages (backend/providers/remote_state)
 *     and the 5-backup tfvars (backup stack now lives in stage 5)
 *   - both credential files: .creds/lz-<env>-infra-ops.env (bootstrap key)
 *     and .creds/lz-<env>.env (lz deploy key)
 *
 * This stage uses LOCAL state (it's the seed for everything else). After
 * running it once, all other stages read its outputs through a local
 * terraform_remote_state (stage0_state_path), see remote_state-<env>.tfvars.
 *
 * Usage:
 *   cd scw-lz/bootstrap
 *   terraform init
 *   terraform plan
 *   terraform apply -auto-approve
 */

terraform {
  required_version = ">= 1.14"
  required_providers {
    scaleway = {
      source = "scaleway/scaleway"
      # >= 2.83: scaleway_iam_saml / iam_scim / iam_scim_token /
      # iam_saml_certificate and the iam_update_saml_configuration action
      # (org SSO).
      version = "~> 2.83"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "scaleway" {
  organization_id = var.organization_id
  project_id      = var.project_id
  region          = var.region
  zone            = var.zone
}

# ---------------------------------------------------------------------------
# Bootstrap Module, infra-ops project, state bucket, bootstrap SA + IAM
# ---------------------------------------------------------------------------

module "bootstrap" {
  source = "../../modules/bootstrap"

  environment     = var.environment
  organization_id = var.organization_id
  region          = var.region
  zone            = var.zone

  infra_ops_project_name = var.infra_ops_project_name

  project_prefix = var.project_prefix

  state_bucket_prefix = var.state_bucket_prefix

  # Org tag policy + toolkit-reserved markers reach the infra-ops state bucket
  # the same way they reach every other resource.
  tags = local.common_tags_map

  enable_state_lock    = var.enable_state_lock
  state_retention_days = var.state_retention_days
  enable_state_sse     = var.enable_state_sse
  api_key_expires_at   = var.api_key_expires_at
}

# ---------------------------------------------------------------------------
# Store bootstrap credentials in Secret Manager for CI/CD use
# ---------------------------------------------------------------------------

resource "scaleway_secret" "bootstrap_credentials" {
  name        = "lz-${var.environment}-bootstrap-credentials"
  description = "Credentials for the bootstrap service account (used by CI/CD)"
  project_id  = module.bootstrap.project_id
  region      = var.region
  tags        = concat(local.common_tags, ["ci-cd", "credentials"])
}

resource "scaleway_secret_version" "bootstrap_credentials" {
  secret_id = scaleway_secret.bootstrap_credentials.id
  region    = var.region
  data = jsonencode({
    access_key     = module.bootstrap.bootstrap_access_key
    secret_key     = module.bootstrap.bootstrap_secret_key
    project_id     = module.bootstrap.project_id
    state_bucket   = module.bootstrap.state_bucket_name
    state_endpoint = module.bootstrap.state_endpoint
  })
}

# ---------------------------------------------------------------------------
# Remote State Backend Config, generated for use by other stages
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Common tags: the org's tag policy (var.common_tags) plus the toolkit-
# reserved markers managed-by / env / stage. Composition is the single
# source of truth in modules/tags; local.common_tags / common_tags_map below
# just alias the module outputs so the rest of this file keeps using
# local.common_tags.
# ---------------------------------------------------------------------------
module "common_tags" {
  source      = "../../modules/tags"
  user_tags   = var.common_tags
  environment = var.environment
  stage_id    = "bootstrap"
}

# Per-stage state paths (stage-1, stage-2, ...)
locals {
  common_tags     = module.common_tags.list
  common_tags_map = module.common_tags.map

  stage_state_paths = {
    "1-security"            = "stage-1/terraform.tfstate"
    "2-networking"          = "stage-2/terraform.tfstate"
    "3-security-appliances" = "stage-3/terraform.tfstate"
    "4-project-factory"     = "stage-4/terraform.tfstate"
  }
}

# ---------------------------------------------------------------------------
# Rendered contents of the generated per-env config files. Written via
# null_resource + local-exec so the files SURVIVE a bootstrap destroy: the
# hashicorp/local `local_file` resource deletes its file on destroy, which
# silently removed the required backend/providers/remote_state/5-backup
# tfvars on every teardown. null_resource deletes nothing; the triggers
# re-render whenever the content changes, and `make bootstrap` regenerates
# them on demand. (The two .creds key files stay as local_file on purpose:
# those ARE secrets that should be removed at teardown.)
# ---------------------------------------------------------------------------
locals {
  backend_cfg_content = templatefile("${path.module}/templates/backend.tfvars.tpl", {
    bucket            = module.bootstrap.state_bucket_name
    endpoint          = module.bootstrap.state_endpoint
    access_key        = module.bootstrap.bootstrap_access_key
    secret_key        = module.bootstrap.bootstrap_secret_key
    organization_id   = var.organization_id
    project_id        = module.bootstrap.project_id
    region            = var.region
    environment       = var.environment
    stage_state_paths = local.stage_state_paths
  })

  providers_cfg_content = templatefile("${path.module}/templates/providers.tfvars.tpl", {
    organization_id = var.organization_id
    project_id      = module.bootstrap.project_id
    region          = var.region
    zone            = var.zone
    environment     = var.environment
  })

  remote_state_cfg_content = templatefile("${path.module}/templates/remote_state.tfvars.tpl", {
    bucket      = module.bootstrap.state_bucket_name
    endpoint    = module.bootstrap.state_endpoint
    access_key  = module.bootstrap.bootstrap_access_key
    secret_key  = module.bootstrap.bootstrap_secret_key
    environment = var.environment
  })

  backup_cfg_content = templatefile("${path.module}/templates/backup.tfvars.tpl", {
    state_bucket_name         = module.bootstrap.state_bucket_name
    state_endpoint            = module.bootstrap.state_endpoint
    infra_ops_project_id      = module.bootstrap.project_id
    lz_project_id             = module.projects[var.environment].id
    backup_bucket_name        = local.backup_bucket_name
    backup_bucket_endpoint    = "https://s3.${var.region}.scw.cloud"
    backup_dr_bucket_name     = local.backup_dr_bucket_name
    backup_dr_bucket_endpoint = "https://s3.${var.dr_region}.scw.cloud"
    backup_dr_region          = var.dr_region
    backup_retention_days     = var.backup_retention_days
    enable_backup_versioning  = var.enable_backup_versioning
    enable_backup_sse         = var.enable_backup_sse
    kms_key_rotation_days     = var.kms_key_rotation_days
  })
}

resource "null_resource" "backend_config" {
  triggers = {
    content = local.backend_cfg_content
  }

  provisioner "local-exec" {
    command = <<-EOT
cat > "${path.module}/../envs/${var.environment}/backend-${var.environment}.tfvars" <<'LZC'
${local.backend_cfg_content}
LZC
EOT
  }
}

# ---------------------------------------------------------------------------
# Generate providers config for downstream stages
# This allows all stages to share the same provider config from bootstrap.
# ---------------------------------------------------------------------------

resource "null_resource" "providers_config" {
  triggers = {
    content = local.providers_cfg_content
  }

  provisioner "local-exec" {
    command = <<-EOT
cat > "${path.module}/../envs/${var.environment}/providers-${var.environment}.tfvars" <<'LZC'
${local.providers_cfg_content}
LZC
EOT
  }
}

# ---------------------------------------------------------------------------
# Generate remote_state.tfvars for downstream stages
# These feed into `data terraform_remote_state` blocks. The S3 vars are used
# for reading OTHER stages' state; stage0_state_path points at THIS stage's
# LOCAL state file so stages 1-6 can resolve the lz-<env> project/keys
# (bootstrap's outputs).
# ---------------------------------------------------------------------------

resource "null_resource" "remote_state_config" {
  triggers = {
    content = local.remote_state_cfg_content
  }

  provisioner "local-exec" {
    command = <<-EOT
cat > "${path.module}/../envs/${var.environment}/remote_state-${var.environment}.tfvars" <<'LZC'
${local.remote_state_cfg_content}
LZC
EOT
  }
}

# ---------------------------------------------------------------------------
# Backup stack bucket names + config for stage 5 (named 5-backup-<env>.tfvars
# to match the numbered per-stage convention). The backup/DR buckets are
# CREATED by stage 5, in the lz-<env> project, under the lz deploy key -
# bootstrap only plans the names/endpoints here. Credentials are deliberately
# NOT included (jobs reuse the keys from backend-<env>.tfvars / SM).
# ---------------------------------------------------------------------------

locals {
  # Shared bucket prefix: user-supplied (state_bucket_prefix, required) or the
  # default lz. Bucket names must be globally unique, so a frozen creation
  # timestamp suffix (module.bootstrap.bucket_suffix) is appended to EVERY
  # bootstrap-named bucket (state, audit, image-import, backup/DR):
  #   <prefix>-<env>-<purpose>-<timestamp>
  # This makes collisions impossible even for the same user prefix or a
  # rebuilt environment.
  bucket_prefix         = var.state_bucket_prefix != null ? var.state_bucket_prefix : "lz"
  bucket_suffix         = module.bootstrap.bucket_suffix
  backup_bucket_name    = "${local.bucket_prefix}-${var.environment}-backup-${local.bucket_suffix}"
  backup_dr_bucket_name = "${local.bucket_prefix}-${var.environment}-backup-dr-${local.bucket_suffix}"
}

resource "null_resource" "backup_config" {
  triggers = {
    content = local.backup_cfg_content
  }

  provisioner "local-exec" {
    command = <<-EOT
cat > "${path.module}/../envs/${var.environment}/5-backup-${var.environment}.tfvars" <<'LZC'
${local.backup_cfg_content}
LZC
EOT
  }
}

# ---------------------------------------------------------------------------
# Persist the bootstrap SA API key to <repo>/.creds/lz-<env>-infra-ops.env
# (gitignored). One key per project: this is the key bound to the infra-ops
# project (raw S3 ops there + org-wide API access). The lz-<env> project has
# its own key (".creds/lz-<env>.env"), generated by this same stage when it
# creates the lz-<env> project + deploy SA below.
# The secret is only shown once by Scaleway at creation time, so bootstrap is
# the ONLY component that ever sees it - it must write it down for the user.
# Stage-1..6 and destroy auto-source these files (load_env_creds), so there is
# no manual copy/paste: run make bootstrap once, then make stage-1..6 "just
# work". The file is written source-able (export KEY=...), 0600.
# ---------------------------------------------------------------------------
resource "local_file" "credentials_env" {
  filename        = "${path.module}/../../.creds/lz-${var.environment}-infra-ops.env"
  file_permission = "0600"
  content         = <<-EOT
    # Generated by scw-lz/bootstrap - bootstrap SA key for ${var.environment}.
    # Default project = ${var.project_prefix}-${var.environment}-infra-ops (raw S3 there + org-wide API).
    # Loaded automatically by scripts/apply.sh / destroy.sh (load_env_creds).
    # Do not commit. Rotate: delete the API key + re-run make bootstrap.
    export SCW_ACCESS_KEY=${module.bootstrap.bootstrap_access_key}
    export SCW_SECRET_KEY=${module.bootstrap.bootstrap_secret_key}
    export ORG_ID=${var.organization_id}
    export PROJECT_ID=${module.bootstrap.project_id}
    export ENV=${var.environment}
    export REGION=${var.region}
    export ZONE=${var.zone}
  EOT
}

# ===========================================================================
# ORG SETUP
# ===========================================================================

locals {
  # -------------------------------------------------------------------------
  # YAML Factory - loads the per-env factory from the env config folder
  # (envs/<env>/data/org-<env>.yaml). Prefer the live <topic>-<env>-demo.yaml
  # when present (real per-env data, gitignored); otherwise fall back to the
  # committed <topic>-<env>.yaml template - so public clones run straight from
  # the template. Merge with optional variable overrides (tfvars) - variables
  # take precedence.
  # -------------------------------------------------------------------------

  factory_file = fileexists("../envs/${var.environment}/data/org-${var.environment}-demo.yaml") ? "../envs/${var.environment}/data/org-${var.environment}-demo.yaml" : "../envs/${var.environment}/data/org-${var.environment}.yaml"

  factory_raw = yamldecode(file(local.factory_file))

  projects          = merge(local.factory_raw.projects, var.projects)
  iam_groups        = merge(local.factory_raw.iam_groups, var.iam_groups)
  service_accounts  = merge(local.factory_raw.service_accounts, var.service_accounts)
  iam_policies      = merge(try(local.factory_raw.iam_policies, {}), var.iam_policies)
  ssh_keys          = merge(local.factory_raw.ssh_keys, var.ssh_keys)
  kms_keys          = merge(local.factory_raw.kms_keys, var.kms_keys)
  audit_log_buckets = merge(local.factory_raw.audit_log_buckets, var.audit_log_buckets)
  secrets           = merge(local.factory_raw.secrets, var.secrets)
  sso               = merge(try(local.factory_raw.sso, {}), var.sso)
}

# ---------------------------------------------------------------------------
# Projects
# ---------------------------------------------------------------------------

module "projects" {
  source = "../../modules/project"
  for_each = {
    for k, v in local.projects : k => v
  }

  name            = "${var.project_prefix}-${each.value.name}"
  description     = lookup(each.value, "description", null)
  organization_id = var.organization_id
  # Reference an existing org-wide project (e.g. prod already created by a
  # previous run) instead of re-creating it. Null = create new.
  project_id = lookup(each.value, "project_id", null)
}

# ---------------------------------------------------------------------------
# IAM Groups
# ---------------------------------------------------------------------------

module "iam_groups" {
  source = "../../modules/iam-group"
  for_each = {
    for k, v in local.iam_groups : k => v
  }

  name            = "lz-${var.environment}-${each.value.name}"
  description     = lookup(each.value, "description", null)
  tags            = concat(local.common_tags, lookup(each.value, "tags", []))
  application_ids = lookup(each.value, "application_ids", [])
  user_ids        = lookup(each.value, "user_ids", [])
  organization_id = var.organization_id
}

# ---------------------------------------------------------------------------
# IAM Service Accounts (Applications)
# ---------------------------------------------------------------------------

module "service_accounts" {
  source = "../../modules/iam-service-account"
  for_each = {
    for k, v in local.service_accounts : k => v
  }

  name                       = "lz-${var.environment}-${each.value.name}"
  description                = lookup(each.value, "description", null)
  tags                       = concat(local.common_tags, lookup(each.value, "tags", []))
  organization_id            = var.organization_id
  create_api_key             = lookup(each.value, "create_api_key", true)
  api_key_description        = lookup(each.value, "api_key_description", "API key for service account")
  api_key_expires_at         = lookup(each.value, "api_key_expires_at", null)
  api_key_default_project_id = lookup(each.value, "api_key_default_project_id", null)
}

# ---------------------------------------------------------------------------
# lz-<env> deploy key (one API key per project)
# ---------------------------------------------------------------------------
# One API key per project. Raw S3 access in Scaleway follows the API key's
# DEFAULT PROJECT (not the org), so:
#   - the bootstrap key lives in .creds/lz-<env>-infra-ops.env and defaults to
#     the infra-ops project (state bucket lives there)
#   - this deploy key lives in .creds/lz-<env>.env and defaults to the
#     lz-<env> project, where stages 1-6 create everything (firewalls, backup
#     buckets in stage 5, team projects in stage 4 and the firewall image
#     bucket in stage 3).
# Bootstrap is the right home: it creates the lz-<env> project in this same
# apply, so the key can be defaulted to it. The key secret is only visible at
# creation - like bootstrap's credentials_env, we persist it to disk here.
# The deploy SA gets the SAME org-wide policies as the bootstrap SA so stages
# 1-6 keep working; the ONLY difference is the default project of the key.
# ---------------------------------------------------------------------------
resource "scaleway_iam_application" "lz_deploy" {
  name            = "lz-${var.environment}-deploy"
  description     = "Deploy SA for stages 1-6 (default project = ${var.project_prefix}-${var.environment})"
  organization_id = var.organization_id
}

resource "scaleway_iam_api_key" "lz_deploy" {
  application_id     = scaleway_iam_application.lz_deploy.id
  description        = "API key for lz-${var.environment}-deploy (stages 1-6)"
  default_project_id = module.projects[var.environment].id
  expires_at         = var.api_key_expires_at

  # Same ForceNew drift guard as the bootstrap key: an org-level credential
  # max duration back-fills expires_at and would force-recreate this key on
  # every apply (the stages 1-6 run with this key - recreation mid-run bricks
  # them). Rotation is manual only. See work item #1.
  lifecycle {
    ignore_changes = [expires_at]
  }
}

# Org-wide deploy rights (mirrors the bootstrap SA - stages need to deploy
# into the LZ project and read remote state; keep identical access).
resource "scaleway_iam_policy" "lz_deploy_org_deploy" {
  name            = "lz-${var.environment}-deploy-org-deploy"
  description     = "lz deploy SA: org-wide deployment rights (AllProductsFullAccess)"
  application_id  = scaleway_iam_application.lz_deploy.id
  organization_id = var.organization_id

  rule {
    organization_id      = var.organization_id
    permission_set_names = ["AllProductsFullAccess"]
  }
}

resource "scaleway_iam_policy" "lz_deploy_org_iam" {
  name            = "lz-${var.environment}-deploy-org-iam"
  description     = "lz deploy SA: org-wide IAM management (IAMManager)"
  application_id  = scaleway_iam_application.lz_deploy.id
  organization_id = var.organization_id

  rule {
    organization_id      = var.organization_id
    permission_set_names = ["IAMManager"]
  }
}

# Persist the lz-<env> deploy key to <repo>/.creds/lz-<env>.env (gitignored).
# Same once-only-secret pattern as the bootstrap credentials_env.
resource "local_file" "lz_deploy_env" {
  filename        = "${path.module}/../../.creds/lz-${var.environment}.env"
  file_permission = "0600"
  content         = <<-EOT
    # Generated by scw-lz/bootstrap - lz deploy SA key for ${var.environment}.
    # Default project = ${var.project_prefix}-${var.environment} (stages 1-6 + raw S3 there).
    # Loaded automatically by scripts/apply.sh / destroy.sh (load_env_creds).
    # Do not commit. Rotate: delete the API key + re-run make bootstrap.
    export SCW_ACCESS_KEY=${scaleway_iam_api_key.lz_deploy.access_key}
    export SCW_SECRET_KEY=${scaleway_iam_api_key.lz_deploy.secret_key}
    export ORG_ID=${var.organization_id}
    export PROJECT_ID=${module.projects[var.environment].id}
    export ENV=${var.environment}
    export REGION=${var.region}
    export ZONE=${var.zone}
  EOT
}

# ---------------------------------------------------------------------------
# IAM Policies, resolve principal keys to actual IDs
# ---------------------------------------------------------------------------

locals {
  iam_policies_resolved = {
    for k, v in local.iam_policies : k => {
      name            = "lz-${var.environment}-${lookup(v, "name", k)}"
      description     = lookup(v, "description", null)
      tags            = concat(local.common_tags, lookup(v, "tags", []))
      organization_id = var.organization_id
      user_id         = lookup(v, "user_id", null)
      group_id        = lookup(v, "group_id", null) != null ? module.iam_groups[lookup(v, "group_id", null)].id : null
      application_id  = lookup(v, "application_id", null) != null ? module.service_accounts[lookup(v, "application_id", null)].id : null
      no_principal    = lookup(v, "no_principal", false)
      rules           = lookup(v, "rules", [])
    }
  }
}

module "iam_policies" {
  source   = "../../modules/iam-policy"
  policies = local.iam_policies_resolved
}

# SSH Keys (auto-generated key pairs)

# Generate private key pairs using the tls provider
resource "tls_private_key" "keys" {
  for_each = local.ssh_keys

  algorithm = lookup(each.value, "algorithm", "ED25519")
  rsa_bits  = lookup(each.value, "rsa_bits", 4096)
}

# Register the generated public keys in Scaleway IAM
resource "scaleway_iam_ssh_key" "keys" {
  for_each = local.ssh_keys

  name       = "lz-${var.environment}-${each.value.name}"
  public_key = tls_private_key.keys[each.key].public_key_openssh
  project_id = module.projects[lookup(each.value, "project_key", "dev")].id
  disabled   = lookup(each.value, "disabled", false)
}

# ---------------------------------------------------------------------------
# Write generated SSH key pairs to the toolkit (scw-lz/keys) on apply,
# and delete them on destroy so no stale secrets linger locally.
# ---------------------------------------------------------------------------
locals {
  generated_ssh_keys = {
    for k, v in local.ssh_keys : k => v
    if lookup(v, "public_key", null) == null
  }
}

resource "terraform_data" "ssh_key_files" {
  for_each = local.generated_ssh_keys

  triggers_replace = [
    tls_private_key.keys[each.key].private_key_openssh,
    tls_private_key.keys[each.key].public_key_openssh,
    var.ssh_key_dir,
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      mkdir -p ${self.triggers_replace[2]}
      cat > ${self.triggers_replace[2]}/${each.key} <<'KEYEOF'
${self.triggers_replace[0]}
KEYEOF
      cat > ${self.triggers_replace[2]}/${each.key}.pub <<'KEYEOF'
${self.triggers_replace[1]}
KEYEOF
      chmod 600 ${self.triggers_replace[2]}/${each.key}
      chmod 644 ${self.triggers_replace[2]}/${each.key}.pub
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${self.triggers_replace[2]}/${each.key} ${self.triggers_replace[2]}/${each.key}.pub"
  }
}

# ---------------------------------------------------------------------------
# Firewall backup exporter keypair (dedicated, always generated)
# Stage 3 composes its public key into the firewall authorized_keys and stage
# 5 mirrors the private key into Secret Manager, so BOTH read it from disk
# (scw-lz/keys-<env>/fw-backup/id_ed25519(.pub), gitignored). It is generated HERE
# at bootstrap - the earliest stage - so stage 3/5 never find it missing
# (work item #5). Not registered in Scaleway IAM: it is a firewall-machine
# key, not a console key.
# ---------------------------------------------------------------------------

resource "tls_private_key" "fw_backup" {
  algorithm = "ED25519"
}

resource "terraform_data" "fw_backup_key_files" {
  triggers_replace = [
    tls_private_key.fw_backup.private_key_openssh,
    tls_private_key.fw_backup.public_key_openssh,
    var.ssh_key_dir,
  ]

  provisioner "local-exec" {
    when    = create
    command = <<-EOT
      mkdir -p ${self.triggers_replace[2]}/fw-backup
      cat > ${self.triggers_replace[2]}/fw-backup/id_ed25519 <<'KEYEOF'
${self.triggers_replace[0]}
KEYEOF
      cat > ${self.triggers_replace[2]}/fw-backup/id_ed25519.pub <<'KEYEOF'
${self.triggers_replace[1]}
KEYEOF
      chmod 600 ${self.triggers_replace[2]}/fw-backup/id_ed25519
      chmod 644 ${self.triggers_replace[2]}/fw-backup/id_ed25519.pub
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${self.triggers_replace[2]}/fw-backup/id_ed25519 ${self.triggers_replace[2]}/fw-backup/id_ed25519.pub; rmdir -p ${self.triggers_replace[2]}/fw-backup 2>/dev/null || true"
  }
}

# ---------------------------------------------------------------------------
# SSH Keys - mirror auto-generated private keys to Secret Manager
# The environment must never depend on a single operator machine: the
# generated private keys are mirrored to Secret Manager as well as disk.
# The value is supplied via the write-only argument (data_wo) so the secret
# content is NOT persisted in Terraform state - only Secret Manager holds it
# as the canonical copy along with the local keypair on disk.
# ---------------------------------------------------------------------------

resource "scaleway_secret" "ssh_key_mirror" {
  for_each = local.generated_ssh_keys

  name        = "lz-${var.environment}-ssh-${each.value.name}"
  description = "Private key mirror for SSH key '${each.value.name}' (auto-generated by bootstrap)"
  project_id  = module.projects[lookup(each.value, "project_key", "dev")].id
  region      = var.region
  tags        = concat(local.common_tags, ["ssh", "keys"])
}

resource "scaleway_secret_version" "ssh_key_mirror" {
  for_each = local.generated_ssh_keys

  secret_id = scaleway_secret.ssh_key_mirror[each.key].id
  region    = var.region
  data_wo   = tls_private_key.keys[each.key].private_key_openssh
}

# ---------------------------------------------------------------------------
# KMS, Customer-Managed Encryption Keys
# ---------------------------------------------------------------------------

module "kms_keys" {
  source = "../../modules/kms"
  for_each = {
    for k, v in local.kms_keys : k => v
  }

  name        = "lz-${var.environment}-${each.value.name}"
  description = lookup(each.value, "description", "KMS key for encryption")
  project_id  = module.projects[lookup(each.value, "project_key", "security")].id
  region      = var.region
  algorithm   = lookup(each.value, "algorithm", "aes_256_gcm")
  usage       = lookup(each.value, "usage", "symmetric_encryption")
  unprotected = lookup(each.value, "unprotected", false)
}

# ---------------------------------------------------------------------------
# Object Storage, Centralized Audit Log Bucket
# ---------------------------------------------------------------------------

module "audit_log_buckets" {
  source = "../../modules/object-storage"
  for_each = {
    for k, v in local.audit_log_buckets : k => v
  }

  name        = "${local.bucket_prefix}-${var.environment}-${each.value.name}-${local.bucket_suffix}"
  project_id  = module.projects[lookup(each.value, "project_key", "security")].id
  region      = var.region
  tags        = merge(local.common_tags_map, lookup(each.value, "tags", { purpose = "audit", compliance = "true" }))
  enable_lock = lookup(each.value, "enable_lock", true)
  enable_sse  = lookup(each.value, "enable_sse", true)
  # Audit buckets are object-locked; a prefix change replaces the bucket name,
  # so force_destroy is required to delete the locked old one (409 otherwise).
  force_destroy = true
}

# ---------------------------------------------------------------------------
# Secret Manager, Store sensitive values
# ---------------------------------------------------------------------------

module "secrets" {
  source = "../../modules/secrets"
  for_each = {
    for k, v in local.secrets : k => v
  }

  name         = "lz-${var.environment}-${each.value.name}"
  description  = lookup(each.value, "description", null)
  project_id   = module.projects[lookup(each.value, "project_key", "security")].id
  region       = var.region
  tags         = concat(local.common_tags, lookup(each.value, "tags", []))
  secret_value = lookup(each.value, "secret_value", null)
}

# Store the CI/CD API key in Secret Manager
resource "scaleway_secret_version" "service_account_keys" {
  for_each = {
    for k, v in local.service_accounts : k => v
    if lookup(v, "create_api_key", true) && lookup(v, "store_key_in_secret_manager", false)
  }

  secret_id = module.secrets[lookup(each.value, "secret_key", "${each.key}-api-key")].id
  data      = module.service_accounts[each.key].secret_key
  region    = var.region
}

# ---------------------------------------------------------------------------
# SSO - org-level identity federation (SAML + SCIM), opt-in.
# Driven by the `sso:` block of the org YAML factory (envs/<env>/data/org-<env>.yaml).
# Implemented in modules/iam-sso. Requires Terraform >= 1.14 (provider Actions).
#
#   sso:
#     authentik:
#       enabled: true
#       entity_id: ...
#       single_sign_on_url: ...
#       enable_scim: true
#       store_scim_token_in_secret_manager: true
#       project_key: dev
#
# Security rules of thumb (see modules/iam-sso/README.md):
#   - members are locked out if SAML is enabled without a reachable IdP;
#     the OWNER account is the break-glass (exempt from SAML)
#   - enable SAML, validate a test member, only then disable password auth
#   - the SCIM bearer token is write-only (data_wo), never in state
# ---------------------------------------------------------------------------

module "sso" {
  source   = "../../modules/iam-sso"
  for_each = local.sso

  organization_id          = var.organization_id
  enabled                  = lookup(each.value, "enabled", false)
  entity_id                = lookup(each.value, "entity_id", null)
  single_sign_on_url       = lookup(each.value, "single_sign_on_url", null)
  enable_scim              = lookup(each.value, "enable_scim", false)
  idp_signing_certificates = lookup(each.value, "certs", [])
}

# Mirror the SCIM bearer token to Secret Manager (write-only via data_wo,
# same pattern as the SSH key / API key mirrors above).
resource "scaleway_secret" "scim_token_mirror" {
  for_each = {
    for k, v in local.sso : k => v
    if lookup(v, "enabled", false) && lookup(v, "enable_scim", false) && lookup(v, "store_scim_token_in_secret_manager", false)
  }

  name        = "lz-${var.environment}-scim-token"
  description = "SCIM bearer token for org SSO (write-only, mirrored via data_wo)"
  project_id  = module.projects[lookup(each.value, "project_key", "security")].id
  region      = var.region
  tags        = concat(local.common_tags, ["sso", "scim"])
}

resource "scaleway_secret_version" "scim_token_mirror" {
  for_each = {
    for k, v in local.sso : k => v
    if lookup(v, "enabled", false) && lookup(v, "enable_scim", false) && lookup(v, "store_scim_token_in_secret_manager", false)
  }

  secret_id = scaleway_secret.scim_token_mirror[each.key].id
  region    = var.region
  data_wo   = module.sso[each.key].scim_bearer_token
}
