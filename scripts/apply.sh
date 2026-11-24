#!/usr/bin/env bash

# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Apply stages in order.
#
# Usage:
#   ./scripts/apply.sh [ENVIRONMENT] [--skip-bootstrap] [--plan] [--stage <stage>]
#
# ENVIRONMENT defaults to $ENV, then "dev". Reads the bootstrap-generated
# per-env config files from scw-lz/envs/<ENV>/ (backend/providers/remote_state).
#   --skip-bootstrap  skip the bootstrap stage (already run)
#   --plan            dry-run only: terraform plan, change nothing.
#   --stage <stage>   run only ONE stage (key "3-security-appliances", number
#                     "3", or alias "stage-3"; also "bootstrap").
#
# Stage metadata + the terraform driver are shared with destroy.sh via
# scripts/lib/stages.sh.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/stages.sh"

# -- CLI ------------------------------------------------------------------
parse_cli apply "$@"

# -- Paths ----------------------------------------------------------------
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ENV_DIR="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}"
if [[ ! -d "${ENV_DIR}" ]]; then
  echo "Error: config folder scw-lz/envs/${ENV_NAME} not found."
  echo "       Create it (see scw-lz/bootstrap/README.md), then run bootstrap first."
  exit 1
fi

# -- Credentials & identity (required) -------------------------------------
load_env_creds "${STAGE_ONLY}"   # sources .creds/lz-<env>.env or .creds/lz-<env>-infra-ops.env (stage-aware)
require_creds

: "${ORG_ID:?ORG_ID must be set - export it (e.g. source .creds/lz-creds.env and export ORG_ID)}"
PROJECT_ID="${PROJECT_ID:-${ORG_ID}}"
REGION="${REGION:-fr-par}"
ZONE="${ZONE:-fr-par-2}"

echo "environment : ${ENV_NAME}"
echo "region      : ${REGION}"
echo "zone        : ${ZONE}"
echo "org id      : ${ORG_ID}"
[[ -n "${STAGE_ONLY}" ]] && echo "stage       : ${STAGE_ONLY}"

# -- Main execution -------------------------------------------------------
for key in "${STAGES_FORWARD[@]}"; do
  [[ -n "${STAGE_ONLY}" && "${key}" != "${STAGE_ONLY}" ]] && continue

  if [[ "${key}" == "bootstrap" ]]; then
    if [[ "${SKIP_BOOTSTRAP}" == false ]]; then
      run_stage "${ACTION}" "${key}"
    else
      echo "skipping bootstrap (already run)"
    fi
    continue
  fi

  # Stage 4 is off by default: runs only with a live demo tfvars or --stage 4.
  if [[ "${key}" == "4-project-factory" && "${STAGE_ONLY}" != "4-project-factory" && ! -f "${ENV_DIR}/4-project-factory-${ENV_NAME}-demo.tfvars" ]]; then
    echo "skipping stage-4: project factory disabled by default (create 4-project-factory-${ENV_NAME}-demo.tfvars or use --stage 4 to enable)"
    continue
  fi
  if [[ "${key}" == "5-backup" && ! -f "${ENV_DIR}/5-backup-${ENV_NAME}.tfvars" ]]; then
    echo "skipping stage-5: scw-lz/envs/${ENV_NAME}/5-backup-${ENV_NAME}.tfvars not found"
    echo "   Create one (see scw-lz/stages/5-backup) to deploy the backup stack."
    continue
  fi

  run_stage "${ACTION}" "${key}"
done

echo ""
echo "done: all requested stages (${ACTION})"
