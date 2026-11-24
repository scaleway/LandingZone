#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Purge leftover S2S VPN PSK secrets.
#
# Managed S2S VPN auto-generates the connection PSK and stores it in Secret
# Manager with PROTECTION (tag "S2S VPN", name "connection_<id>"). Terraform
# never owns that secret (scaleway_s2s_vpn_connection has no psk input), so
# destroying the VPN leaves it behind and it accumulates across rebuilds.
# This helper finds leftover platform-generated secrets: list -> unprotect ->
# delete. Scoped to a single project (default: the env's tenant project,
# resolved from bootstrap's LOCAL state - destroyed last, so always present
# when destroy.sh runs the purge), so other environments are never touched.
#
#   ./scripts/delete_vpn_secrets.sh [ENV] [--project <uuid>] [-y]
#                                   [--pattern <name-glob>] [--dry-run]
#                                   [--creds <identity>]
#
#   [ENV]               environment (default: $ENV, then dev)
#   --project <uuid>    ONLY purge S2S secrets in this project.
#   -y                  skip the confirmation prompt (dangerous)
#   --pattern <glob>    extra name filter (default: any "S2S VPN" secret)
#   --dry-run           list only, never delete (also the default whenever
#                       no project could be determined)
#   --creds <identity>  creds identity (default: "lz-<env>-infra-ops")
#
# CREDENTIALS: the lz-<env> DEPLOY key cannot read Secret Manager ("insufficient
# permissions: list secret"). Use the bootstrap key (default, .creds/lz-<env>-
# infra-ops.env) or a key with SecretManagerFullAccess.
#
# PROJECT RESOLUTION (no --project): reads the env tenant project UUID from
# bootstrap's local state ("project_ids[<env>]") - requires the env to be
# bootstrapped; if it cannot be determined the script lists only.
#
# Recommended wiring (already in destroy.sh): after all stages are destroyed,
#   ./scripts/delete_vpn_secrets.sh <ENV> -y
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # REPO_ROOT is read by lib/stages.sh load_env_creds
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/stages.sh"

command -v scw >/dev/null 2>&1 || { echo "error: 'scw' CLI not found (brew install scaleway-cli)." >&2; exit 1; }

ENV_NAME=""
PROJECT_ARG=""
ASSUME_YES=0
DRY_RUN=0
PATTERN=".*"
CREDS_IDENTITY=""
# Parse args: first plain arg = ENV name (like delete_s3.sh), everything else
# is flags.
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project)  PROJECT_ARG="$2"; shift 2 ;;
    --pattern)  PATTERN="$2"; shift 2 ;;
    --creds)    CREDS_IDENTITY="$2"; shift 2 ;;
    -y)         ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  sed -n '2,35p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          ARGS+=("$1"); shift ;;
  esac
done
ENV_NAME="${ARGS[0]:-${ENV:-dev}}"

# -- Credentials ------------------------------------------------------------
load_env_creds "${CREDS_IDENTITY:-lz-${ENV_NAME}-infra-ops}"
if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" ]]; then
  echo "error: SCW_ACCESS_KEY and SCW_SECRET_KEY are not set." >&2
  echo "       Fill .creds/lz-${ENV_NAME}-infra-ops.env or export them." >&2
  exit 1
fi

ENV_DIR="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}"
REGION="${REGION:-fr-par}"

# -- Organization id --------------------------------------------------------
ORG_ID="${ORG_ID:-}"
if [[ -z "${ORG_ID}" ]]; then
  ORG_ID="$(sed -n 's/^organization_id[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
    "${ENV_DIR}/providers-${ENV_NAME}.tfvars" 2>/dev/null | head -1)"
fi
if [[ -z "${ORG_ID}" ]]; then
  echo "error: cannot determine organization_id (set ORG_ID or bootstrap the env first)." >&2
  exit 1
fi

# -- Target project ---------------------------------------------------------
PROJECT="${PROJECT_ARG:-}"
if [[ -z "${PROJECT}" ]]; then
  # Read the env tenant project from bootstrap's LOCAL state (destroyed
  # last, so it is still present when destroy.sh runs this purge).
  if command -v terraform >/dev/null 2>&1 && \
     [[ -f "${ENV_DIR}/bootstrap-${ENV_NAME}.tfstate" ]]; then
    PROJECT="$(cd "${REPO_ROOT}/scw-lz/bootstrap" \
      && terraform init -input=false >/dev/null 2>&1 \
      && terraform output -state="../envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate" -json project_ids 2>/dev/null \
      | jq -r --arg k "${ENV_NAME}" '.[$k] // empty' 2>/dev/null || true)"
  fi
fi
if [[ -z "${PROJECT}" ]]; then
  echo "warn: could not resolve the '$ENV_NAME' tenant project (pass --project <uuid>)." >&2
  echo "      Listing S2S leftovers across all projects instead - nothing will be deleted." >&2
  echo ""
  DRY_RUN=1
fi

# -- Discover S2S leftovers -------------------------------------------------
LIST="$(scw secret secret list organization-id="${ORG_ID}" region="${REGION}" -o json 2>/dev/null || echo '[]')"
MATCHES="$(jq -c --arg proj "${PROJECT}" --arg pat "${PATTERN}" \
  '[.[] | select((.tags // []) | index("S2S VPN") != null) |
        select(($proj == "") or (.project_id == $proj)) |
        select(.name | test($pat; "i"))]' <<< "${LIST}")"

COUNT="$(jq 'length' <<< "${MATCHES}")"
echo ""
echo "organization : ${ORG_ID}"
if [[ -n "${PROJECT}" ]]; then
  echo "project      : ${PROJECT}"
else
  echo "project      : (all projects - listing only)"
fi
echo "S2S leftovers: ${COUNT}  (tag \"S2S VPN\")"
if [[ "${COUNT}" -eq 0 ]]; then
  echo "Nothing to purge - already clean."
  exit 0
fi

jq -r '.[] | "  - \(.project_id // "?")\t\(.name)\tprotected=\(.protected)\t\(.id)"' <<< "${MATCHES}"

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "(dry run - not deleted. Re-run with --project <uuid> to purge.)"
  exit 0
fi

# -- Confirm ----------------------------------------------------------------
if [[ "${ASSUME_YES}" -ne 1 ]]; then
  read -r -p "Type the project id (${PROJECT}) to confirm deletion of these ${COUNT} secret(s): " confirm
  if [[ "${confirm}" != "${PROJECT}" ]]; then
    echo "Aborted (confirmation did not match)."
    exit 1
  fi
fi

# -- Purge: unprotect (if protected) then delete ----------------------------
purged=0
failed=0
while IFS=$'\t' read -r id name protected; do
  if [[ "${protected}" == "true" ]]; then
    echo "==> unprotecting ${name} (${id})"
    scw secret secret unprotect "${id}" region="${REGION}" >/dev/null 2>&1 \
      || { echo "    [FAIL] unprotect ${id}" >&2; failed=$((failed+1)); continue; }
  fi
  echo "==> deleting ${name} (${id})"
  if scw secret secret delete "${id}" region="${REGION}" >/dev/null 2>&1; then
    purged=$((purged+1))
  else
    echo "    [FAIL] delete ${id}" >&2
    failed=$((failed+1))
  fi
done < <(jq -r '.[] | "\(.id)\t\(.name)\t\(.protected)"' <<< "${MATCHES}")

echo ""
echo "Purged ${purged} leftover S2S VPN secret(s); ${failed} failed."

# -- Verify ----------------------------------------------------------------
REMAIN="$(scw secret secret list organization-id="${ORG_ID}" region="${REGION}" -o json 2>/dev/null \
  | jq -c --arg proj "${PROJECT}" '[.[] | select((.tags // []) | index("S2S VPN") != null) | select(.project_id == $proj)]' \
  | jq 'length')"
echo "Remaining S2S leftovers in ${PROJECT}: ${REMAIN}"
