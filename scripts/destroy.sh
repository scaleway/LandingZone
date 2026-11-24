#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Destroy stages in reverse order.
#
# Usage:
#   ./scripts/destroy.sh [ENVIRONMENT] [--skip-bootstrap] [--stage <stage>]
#                        [--everything]
#
# ENVIRONMENT defaults to $ENV, then "dev". Destroys stages in reverse
# registry order using the per-env config in scw-lz/envs/<ENV>/.
#   --skip-bootstrap  keep the foundation (state bucket, projects, IAM)
#   --stage <stage>   destroy only ONE stage (key, number, or alias; also
#                     "bootstrap"). --stage always wins over the defaults.
#                     "bootstrap" auto-loads the org-level owner key
#                     (.creds/lz-creds.env): its own SA keys cannot destroy it
#                     (self-brick guard, see scripts/lib/stages.sh).
#   --everything      also destroy the foundation: stage-1 + bootstrap.
#
# DEFAULT (no --everything): only the WORKLOAD stages (2-6) are destroyed;
# the stage-1 security baseline and the bootstrap foundation are kept. A full
# teardown is an explicit choice.
#
# Stage metadata + terraform driver are shared with apply.sh via
# scripts/lib/stages.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/stages.sh"

# -- CLI ------------------------------------------------------------------
parse_cli destroy "$@"

REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# Bootstrap destroy needs an ORG-LEVEL key (self-brick guard refuses its own
# SA keys). Prefer .creds/lz-creds.env when bootstrap is the target; any
# user-exported key in the shell already wins (loader never overrides it).
if [[ "${STAGE_ONLY:-}" == "bootstrap" && -f "${REPO_ROOT}/.creds/lz-creds.env" ]]; then
  load_env_creds "lz-creds"
else
  load_env_creds "${STAGE_ONLY}"   # .creds/lz-<env>.env or lz-<env>-infra-ops.env
fi
require_creds

: "${ORG_ID:?ORG_ID must be set - export it (e.g. source .creds/lz-creds.env and export ORG_ID)}"
PROJECT_ID="${PROJECT_ID:-${ORG_ID}}"
REGION="${REGION:-fr-par}"
ZONE="${ZONE:-fr-par-2}"

echo "topology settings:"
echo "  ORG_ID     = ${ORG_ID}"
echo "  PROJECT_ID = ${PROJECT_ID}"
echo "  ENV        = ${ENV_NAME}"
echo "  REGION     = ${REGION}"
echo "  ZONE       = ${ZONE}"
[[ -n "${STAGE_ONLY}" ]] && echo "  STAGE      = ${STAGE_ONLY}"
echo ""

ENV_DIR="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}"

# Validate config files exist (already bootstrapped)
for f in "${ENV_DIR}/backend-${ENV_NAME}.tfvars" \
         "${ENV_DIR}/providers-${ENV_NAME}.tfvars" \
         "${ENV_DIR}/remote_state-${ENV_NAME}.tfvars"; do
  if [[ ! -f "${f}" ]]; then
    echo "Error: missing ${f} -- cannot destroy without bootstrap config."
    exit 1
  fi
done

# -- Destroy in reverse order (bootstrap last) ----------------------------
for ((i = ${#STAGES_FORWARD[@]} - 1; i >= 0; i--)); do
  key="${STAGES_FORWARD[$i]}"
  [[ -z "${STAGE_ONLY}" || "${key}" == "${STAGE_ONLY}" ]] || continue
  [[ "${key}" == "bootstrap" ]] && continue   # handled below

  # Security baseline kept unless --everything (policies / Cockpit / KMS /
  # secrets / security groups); an explicit --stage 1 still destroys it.
  if [[ -z "${STAGE_ONLY}" && "${INCLUDE_FOUNDATION}" == false && "${key}" == "1-security" ]]; then
    echo "skipping stage-1: security baseline kept (full teardown: make destroy STAGE=1 then STAGE=bootstrap)"
    continue
  fi

  if [[ "${key}" == "4-project-factory" && "${STAGE_ONLY}" != "4-project-factory" && ! -f "${ENV_DIR}/4-project-factory-${ENV_NAME}-demo.tfvars" ]]; then
    # A missing demo tfvars does not prove stage-4 was never deployed (the
    # file can be removed after an apply, orphaning real resources). Decide
    # by remote state instead: destroy when stage-4 state exists, skip only
    # when provably absent (e.g. no S3 creds - test harness).
    rstate_cfg="${ENV_DIR}/remote_state-${ENV_NAME}.tfvars"
    s4_bucket="$(sed -n 's/^state_bucket[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${rstate_cfg}" | head -1)"
    s4_ep="$(sed -n 's/^state_endpoint[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${rstate_cfg}" | head -1)"
    s4_ak="$(sed -n 's/^state_access_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${rstate_cfg}" | head -1)"
    s4_sk="$(sed -n 's/^state_secret_key[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${rstate_cfg}" | head -1)"
    s4_state_exists=1
    if [[ -n "${s4_bucket}" && -n "${s4_ak}" && -n "${s4_sk}" ]]; then
      if AWS_ACCESS_KEY_ID="${s4_ak}" AWS_SECRET_ACCESS_KEY="${s4_sk}" \
         aws s3api head-object --bucket "${s4_bucket}" --key "stage-4/terraform.tfstate" \
         --endpoint-url "${s4_ep:-https://s3.fr-par.scw.cloud}" >/dev/null 2>&1; then
        s4_state_exists=0
      fi
    fi
    if [[ "${s4_state_exists}" -eq 1 ]]; then
      echo "skipping stage-4: project factory disabled by default (create 4-project-factory-${ENV_NAME}-demo.tfvars or use --stage 4 to enable)"
      continue
    fi
    echo "note: stage-4 demo tfvars absent but remote state present - destroying leftover project factory"
  fi
  if [[ "${key}" == "5-backup" && ! -f "${ENV_DIR}/5-backup-${ENV_NAME}.tfvars" ]]; then
    echo "skipping stage-5: envs/${ENV_NAME}/5-backup-${ENV_NAME}.tfvars not found"
    continue
  fi

  # Stage-5 owns the backup/DR buckets: empty them first so terraform can
  # delete the (now empty) buckets. DR bucket lives in the DR region (tfvars).
  if [[ "${key}" == "5-backup" ]]; then
    backup_cfg="${ENV_DIR}/5-backup-${ENV_NAME}.tfvars"
    bb="$(sed -n 's/^backup_bucket_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${backup_cfg}" | head -1)"
    drb="$(sed -n 's/^backup_dr_bucket_name[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${backup_cfg}" | head -1)"
    drr="$(sed -n 's/^backup_dr_region[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${backup_cfg}" | head -1)"
    if [[ -n "${bb}" ]]; then
      echo "==> emptying backup bucket '${bb}'"
      "${SCRIPT_DIR}/delete_s3.sh" "${bb}" "${ENV_NAME}" --empty-only -y || true
      echo ""
    fi
    if [[ -n "${drb}" ]]; then
      dr_args=()
      [[ -n "${drr}" ]] && dr_args+=("--region" "${drr}")
      echo "==> emptying DR backup bucket '${drb}' (${drr:-fr-par})"
      "${SCRIPT_DIR}/delete_s3.sh" "${drb}" "${ENV_NAME}" --empty-only -y "${dr_args[@]+"${dr_args[@]}"}" || true
      echo ""
    fi
  fi

  # Stage-4 owns per-project object buckets: empty them before the destroy
  # (mirrors stage-5). The factory yaml is optional - guard so a missing one
  # cannot fail the pipeline.
  if [[ "${key}" == "4-project-factory" ]] && command -v yq >/dev/null 2>&1; then
    s4_yaml=""
    for y in "${ENV_DIR}/data/projects-${ENV_NAME}-demo.yaml" \
            "${ENV_DIR}/data/projects-${ENV_NAME}.yaml"; do
      [[ -f "${y}" ]] && s4_yaml="${y}" && break
    done
    if [[ -n "${s4_yaml}" ]]; then
      while IFS= read -r bn; do
        [[ -z "${bn}" ]] && continue
        b="lz-${ENV_NAME}-${bn}"
        echo "==> emptying project-factory bucket '${b}'"
        "${SCRIPT_DIR}/delete_s3.sh" "${b}" "${ENV_NAME}" --empty-only -y || true
        echo ""
      done < <(yq '(.object_buckets // {})[] | .name' "${s4_yaml}" 2>/dev/null)
    fi
  fi

  # Stage-3 owns the firewall image-import bucket: empty it first (terraform
  # refuses non-empty buckets), keep it in place via --empty-only. Name:
  # FW_IMAGE_BUCKET override > factory yaml > lz-<env>-image-import.
  if [[ "${key}" == "3-security-appliances" ]]; then
    img_bucket="${FW_IMAGE_BUCKET:-}"
    for yaml in "${ENV_DIR}/data/security-appliances-${ENV_NAME}-demo.yaml" \
                "${ENV_DIR}/data/security-appliances-${ENV_NAME}.yaml"; do
      [[ -f "${yaml}" ]] && img_bucket="$(sed -n 's/^image_bucket_name:[[:space:]]*//p' "${yaml}" | head -1 | tr -d '"')"
      [[ -n "${img_bucket}" ]] && break
    done
    # Fallback: state_bucket_prefix (default lz) + bootstrap creation-timestamp
    # suffix, i.e. <prefix>-<env>-image-import-<timestamp>. Guard the sed so a
    # missing demo tfvars cannot fail the pipeline under set -o pipefail.
    if [[ -z "${img_bucket}" ]]; then
      pfx=""
      if [[ -f "${ENV_DIR}/3-security-appliances-${ENV_NAME}-demo.tfvars" ]]; then
        pfx="$(sed -n 's/.*state_bucket_prefix[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${ENV_DIR}/3-security-appliances-${ENV_NAME}-demo.tfvars" | head -1)"
      fi
      pfx="${pfx:-lz}"
      # Same frozen timestamp the stage derives from bootstrap's bucket_suffix;
      # fall back to the plain name if unknown. || true: jq exits non-zero on a
      # missing file and set -e would abort the teardown.
      bcp_sfx="$(jq -r '.outputs.bucket_suffix.value // empty' "${ENV_DIR}/bootstrap-${ENV_NAME}.tfstate" 2>/dev/null || true)"
      if [[ -n "${bcp_sfx}" ]]; then
        img_bucket="${pfx}-${ENV_NAME}-image-import-${bcp_sfx}"
      else
        img_bucket="${pfx}-${ENV_NAME}-image-import"
      fi
    fi
    echo "==> emptying image-import bucket '${img_bucket}' (objects only; terraform owns the bucket)"
    "${SCRIPT_DIR}/delete_s3.sh" "${img_bucket}" "${ENV_NAME}" --empty-only -y || true
    echo ""
  fi

  run_stage destroy "${key}"
done

# Managed S2S VPN PSKs are platform-created, PROTECTED secrets terraform
# never owns - purge them while the tenant project id is still resolvable
# from bootstrap's local state. Non-fatal.
if [[ -z "${STAGE_ONLY}" || "${STAGE_ONLY}" == "6-interconnection" ]]; then
  echo ""
  echo "==> purging leftover S2S VPN PSK secrets for ${ENV_NAME}"
  "${SCRIPT_DIR}/delete_vpn_secrets.sh" "${ENV_NAME}" -y || true
  echo ""
fi

# -- Post-destroy orphan check ----------------------------------------------
# Stage-1 resources (SGs / KMS / secrets / Cockpit) delete async/soft: a
# DELETE can return success while the resource survives with no state left to
# track it. Check for leftovers while the lz keys and .creds are still intact
# (before the bootstrap block wipes them), in a SUBSHELL so the creds it
# loads never leak into the teardown.
check_stage1_orphans() {
  local opfx ocreds leftovers=0 zone line
  local lz_pid bootstrap_tfstate bootstrap_ids
  opfx="lz-${ENV_NAME}-"
  ocreds="${REPO_ROOT}/.creds/lz-${ENV_NAME}.env"

  grace() { echo "  [orphan-check] $*"; }

  # items_named <stdin-json> <list-key>: "<id>\t<name>\t<zone/region>" for
  # every env-prefixed item not owned by bootstrap (BOOTSTRAP_IDS whitelist).
  items_named() {
    local lk="$1"
    PREFIX="${opfx}" LISTKEY="${lk}" BOOTSTRAP_IDS="${bootstrap_ids}" python3 -c '
import sys, json, os
pfx = os.environ["PREFIX"]
lk  = os.environ["LISTKEY"]
keep = set(os.environ.get("BOOTSTRAP_IDS", "").split())
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
items = d if isinstance(d, list) else d.get(lk, [])
out = []
for it in items:
    nm = it.get("name", "")
    iid = (it.get("id", "") or "").split("/")[-1]
    if nm.startswith(pfx) and iid not in keep:
        out.append("\t".join([it.get("id",""), nm, it.get("zone", it.get("region",""))]))
print("\n".join(out))
'
  }

  collect_items() { # collect_items <label> <list-key> <cmd...> -> bumps leftovers
    local label="$1" lk="$2"; shift 2
    local out line
    out="$("$@" -o json 2>/dev/null | items_named "${lk}")" || true
    if [[ -n "${out}" ]]; then
      echo ""
      echo "  !!! ${label} leftovers (${opfx}*), destroyed stage-1 but these survived:"
      while IFS= read -r line; do
        echo "      ${line}"
        ((leftovers++)) || true
      done <<< "${out}"
    fi
  }

  if ! command -v scw >/dev/null 2>&1; then
    grace "scw CLI not found, skipping leftover check (install scw to enable it)"
    return 0
  fi
  if [[ ! -f "${ocreds}" ]]; then
    grace "creds ${ocreds} not found (bootstrap already destroyed?), cannot verify leftovers via CLI; check the console project for '${opfx}' leftovers"
    return 0
  fi

  # shellcheck disable=SC1090
  set -a
  source "${ocreds}"
  set +a

  # Query the stage-1 project explicitly: scw otherwise falls back to the CLI
  # config default project and would report the wrong resource set.
  lz_pid="${PROJECT_ID:-}"

  # Exclude resources that belong to bootstrap (KMS default key, bootstrap/
  # cicd/ssh secrets, ...): they are supposed to survive a keep-bootstrap run.
  # Owning IDs come from the per-env local bootstrap state.
  bootstrap_tfstate="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate"
  bootstrap_ids=""
  if [[ -f "${bootstrap_tfstate}" ]]; then
    bootstrap_ids="$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
ids = set()
for r in d.get("resources", []):
    if r.get("type") in (
        "scaleway_key_manager_key", "scaleway_secret",
        "scaleway_instance_security_group", "scaleway_cockpit_source",
        "scaleway_cockpit_token",
    ):
        for inst in r.get("instances", []):
            iid = (inst.get("attributes", {}).get("id") or "").split("/")[-1]
            if iid:
                ids.add(iid)
print(" ".join(sorted(ids)))
' "${bootstrap_tfstate}")"
  fi

  local -a pid_args=()
  [[ -n "${lz_pid}" ]] && pid_args=("project-id=${lz_pid}")

  # 1. security groups (both zones)
  for zone in fr-par-1 fr-par-2; do
    collect_items "Security groups (${zone})" "security_groups" \
      scw instance security-group list "${pid_args[@]+"${pid_args[@]}"}" "zone=${zone}"
  done
  # 2. key manager keys
  collect_items "Key Manager keys" "keys" \
    scw keymanager key list "${pid_args[@]+"${pid_args[@]}"}" "region=${REGION:-fr-par}"
  # 3. secret manager secrets
  collect_items "Secret Manager secrets" "secrets" \
    scw secret secret list "${pid_args[@]+"${pid_args[@]}"}" "region=${REGION:-fr-par}"
  # 4. cockpit data sources / tokens (deploy SA often lacks read cockpit)
  if scw cockpit data-source list "region=${REGION:-fr-par}" >/dev/null 2>&1; then
    collect_items "Cockpit data sources" "data_sources" \
      scw cockpit data-source list "region=${REGION:-fr-par}"
  else
    grace "cannot list Cockpit resources with the current SA (read cockpit denied), check data sources & tokens manually in the console"
  fi

  if (( leftovers > 0 )); then
    echo ""
    echo "  !! ${leftovers} Stage-1 leftover(s) found, terraform destroy reported success but"
    echo "     Scaleway kept them (async/soft-delete). Clean them with the scw CLI:"
    echo "       source ${ocreds}"
    echo "       scw instance security-group delete <id...> zone=fr-par-1   # per zone"
    echo "       scw keymanager key delete <id> region=${REGION:-fr-par}"
    echo "       scw secret secret delete <id> region=${REGION:-fr-par}"
    echo "       scw cockpit data-source delete <id>  /  scw cockpit token delete <id>"
    return 1
  fi
  grace "no '${opfx}' leftovers detected, stage-1 cleanup verified"
  return 0
}

stage1_in_destroy=""
if [[ -z "${STAGE_ONLY}" && "${INCLUDE_FOUNDATION}" == true ]]; then
  stage1_in_destroy=1
elif [[ "${STAGE_ONLY}" == "1-security" ]]; then
  stage1_in_destroy=1
fi
if [[ -n "${stage1_in_destroy}" ]]; then
  echo ""
  echo "==> verifying no Stage-1 leftovers (SG / KMS / Secret / Cockpit) for ${ENV_NAME}"
  ( check_stage1_orphans ) || true
fi

# Bootstrap is destroyed last - only when requested (no --stage filter, or
# --stage bootstrap) and the foundation is in the set. Default `make destroy`
# keeps it.
if [[ -z "${STAGE_ONLY}" || "${STAGE_ONLY}" == "bootstrap" ]]; then
  if [[ "${SKIP_BOOTSTRAP}" == true ]]; then
    echo "skipping bootstrap (--skip-bootstrap)"
  elif [[ "${INCLUDE_FOUNDATION}" == false && -z "${STAGE_ONLY}" ]]; then
    echo "skipping bootstrap: foundation kept (full teardown: make destroy STAGE=bootstrap)"
  else
    # Bootstrap teardown order:
    #   1. delete the object-locked (GOVERNANCE, 365d) state bucket via S3 +
    #      --bypass-governance-retention, with the infra-ops bootstrap key -
    #      while the key is still alive.
    #   2. state rm bucket + bootstrap IAM + local_file creds BEFORE destroy:
    #      the destroy graph would revoke the SA keys / delete the creds that
    #      step 1 needed.
    #   3. destroy then only removes the infra-ops project.
    #   4. delete_iam.sh purges env IAM last - SA keys must outlive everything.
    state_bucket="$(sed -n 's/^bucket[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "${ENV_DIR}/backend-${ENV_NAME}.tfvars" | head -1)"
    if [[ -n "${state_bucket}" ]]; then
      echo "==> deleting state bucket '${state_bucket}' via S3 (object-locked: S3 API + bypass only)"
      if ! "${SCRIPT_DIR}/delete_s3.sh" "${state_bucket}" "${ENV_NAME}" -y --creds "lz-${ENV_NAME}-infra-ops"; then
        echo ""
        echo "error: state bucket '${state_bucket}' could not be deleted." >&2
        echo "       A leftover object-locked bucket blocks the infra-ops project destroy," >&2
        echo "       so the teardown is ABORTED here - fix the bucket deletion and re-run" >&2
        echo "       'make destroy STAGE=bootstrap ENV=${ENV_NAME}' (the rest is untouched)." >&2
        exit 1
      fi
      echo ""
    fi

    # Detach resources that must outlive the destroy graph; state rm errors
    # are non-fatal. Run the self-brick guard FIRST: once the SA keys leave
    # the state, the in-run_stage guard has nothing to compare against.
    BOOTSTRAP_STATE="${ENV_DIR}/bootstrap-${ENV_NAME}.tfstate"
    if [[ -f "${BOOTSTRAP_STATE}" ]]; then
      # Same guard as run_stage, before the detach: refuse to drive the
      # destroy with the state's own SA keys.
      while IFS= read -r _own; do
        [[ -n "${_own}" && "${SCW_ACCESS_KEY:-}" == "${_own}" ]] || continue
        cat >&2 <<EOF

error: refusing to destroy bootstrap with its own service-account key (${_own}).

       Detaching the IAM resources from the state happens right before the
       destroy, but the bootstrap SA key must NOT be the driving key: its
       grants die with the stage and the cleanup would half-die. Export an
       ORG-LEVEL key (e.g. source .creds/lz-creds.env) and re-run:

         set -a; source .creds/lz-creds.env; set +a
         make destroy STAGE=bootstrap ENV=${ENV_NAME}
EOF
        exit 1
      done < <(
        jq -r '.resources[]? | select(.type=="scaleway_iam_api_key") | .instances[0].attributes.access_key' "${BOOTSTRAP_STATE}" 2>/dev/null
      )
    fi
    echo "==> detaching IAM + state bucket from bootstrap terraform state (IAM must die last)"
    if [[ -f "${BOOTSTRAP_STATE}" ]]; then
      (
        cd "${REPO_ROOT}/scw-lz/bootstrap"
        terraform init -input=false >/dev/null 2>&1 || true
        # Addresses are relative to scw-lz/bootstrap (infra-ops in module
        # "bootstrap", lz deploy SA at the stage root). Detach the local_file
        # creds too: destroying them would delete the .creds the bucket delete
        # above needs.
        terraform state rm \
          -state="../envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate" \
          module.bootstrap.scaleway_object_bucket.terraform_state \
          module.bootstrap.scaleway_object_bucket_lock_configuration.terraform_state \
          module.bootstrap.scaleway_object_bucket_server_side_encryption_configuration.terraform_state \
          module.bootstrap.scaleway_iam_api_key.bootstrap \
          module.bootstrap.scaleway_iam_application.bootstrap \
          module.bootstrap.scaleway_iam_policy.bootstrap \
          module.bootstrap.scaleway_iam_policy.bootstrap_org_deploy \
          module.bootstrap.scaleway_iam_policy.bootstrap_org_iam \
          scaleway_iam_api_key.lz_deploy \
          scaleway_iam_application.lz_deploy \
          scaleway_iam_policy.lz_deploy_org_deploy \
          scaleway_iam_policy.lz_deploy_org_iam \
          local_file.credentials_env \
          local_file.lz_deploy_env \
          >/dev/null 2>&1 || true
      )
    fi

    run_stage destroy "bootstrap"

    # IAM dies last: detached above so terraform destroy never touches it and
    # its SA key stays valid for every earlier step; delete_iam.sh runs after
    # everything else is gone.
    echo ""
    echo "==> deleting env IAM for ${ENV_NAME} (literal last step - must outlive every resource)"
    "${SCRIPT_DIR}/delete_iam.sh" "${ENV_NAME}" -y || true

    # Remove local creds only now - the bucket delete above needed the
    # bootstrap key. Non-fatal: a leftover gitignored creds file beats
    # failing the teardown.
    for _cf in "${REPO_ROOT}/.creds/lz-${ENV_NAME}-infra-ops.env" "${REPO_ROOT}/.creds/lz-${ENV_NAME}.env"; do
      if [[ -f "${_cf}" ]]; then
        echo "==> removing local creds file ${_cf} (last step - after IAM is gone)"
        rm -f "${_cf}"
      fi
    done
    echo ""
  fi
fi

echo ""
echo "done: all requested stages destroyed"
