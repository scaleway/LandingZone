#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Purge leftover env-scoped IAM.
#
# Terraform's destroy graph revokes the bootstrap/lz-deploy SA keys early
# (api_keys/policies are destroyed before the state bucket and projects), so
# a teardown can never rely on the SA keys past the earliest stages and
# env-scoped IAM can never be destroyed strictly last in-graph. This helper
# is destroy.sh's literal last step: it deletes whatever IAM the bootstrap
# destroy left over (or a partial destroy orphaned) plus the .creds leftovers
# terraform does not reach.
#
# Scoped to the env by the `lz-<env>-` prefix, so other environments and your
# own org key are never touched. Deletes: IAM policies/groups, API keys of
# purged applications, applications (keys go with them), SSH keys. Bootstrap
# never creates IAM users.
#
#   ./scripts/delete_iam.sh [ENV] [-y] [--dry-run] [--prefix <regex>]
#                          [--creds <identity>]
#
#   [ENV]               environment (default: $ENV, then dev)
#   -y                  skip the confirmation prompt (dangerous)
#   --dry-run           list only, never delete
#   --prefix <regex>    name prefix filter (default: ^lz-<env>-)
#   --creds <identity>  creds identity (default: "lz-<env>-infra-ops")
#
# CREDENTIALS: needs org-wide IAMManager to see and delete every IAM object.
# Both env keys carry it, but a full teardown destroys them - a standalone
# run needs an ORG-LEVEL key (e.g. `source .creds/lz-creds.env`). destroy.sh
# already drives the teardown under the org key.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # REPO_ROOT is read by lib/stages.sh load_env_creds
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/stages.sh"

command -v scw >/dev/null 2>&1 || { echo "error: 'scw' CLI not found (brew install scaleway-cli)." >&2; exit 1; }

ENV_NAME=""
PREFIX=""
ASSUME_YES=0
DRY_RUN=0
CREDS_IDENTITY=""
# Parse args: first plain arg = ENV name (like delete_s3.sh), everything else
# is flags.
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)   PREFIX="$2"; shift 2 ;;
    --creds)    CREDS_IDENTITY="$2"; shift 2 ;;
    -y)         ASSUME_YES=1; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    -h|--help)  sed -n '2,31p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          ARGS+=("$1"); shift ;;
  esac
done
ENV_NAME="${ARGS[0]:-${ENV:-dev}}"
PREFIX="${PREFIX:-^lz-${ENV_NAME}-}"

# -- Credentials ------------------------------------------------------------
load_env_creds "${CREDS_IDENTITY:-lz-${ENV_NAME}-infra-ops}"
if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" ]]; then
  echo "error: SCW_ACCESS_KEY and SCW_SECRET_KEY are not set." >&2
  echo "       Fill .creds/lz-${ENV_NAME}-infra-ops.env or export an org-level key." >&2
  exit 1
fi

ENV_DIR="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}"

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

# -- Discover leftovers -----------------------------------------------------
echo ""
echo "organization : ${ORG_ID}"
echo "prefix       : ${PREFIX}"

# iam_query <label> <cmd...>: run an IAM list query; on failure print a
# warning and set DISCOVERY_FAILED instead of echoing '[]' - a broken query
# must never be reported as "already clean".
DISCOVERY_FAILED=0
iam_query() {
  local label="$1"; shift
  local out rc=0
  out="$("$@" 2>&1)" || rc=$?
  if [[ ${rc} -ne 0 ]]; then
    echo "  [WARN] ${label} discovery failed (rc=${rc}): ${out}" >&2
    DISCOVERY_FAILED=1
    echo '[]'
  else
    printf '%s\n' "${out}"
  fi
}

APPLIST="$(iam_query "applications" scw iam application list organization-id="${ORG_ID}" -o json)"
APPIDS="$(jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat)) | .id]' <<< "${APPLIST}")"

POLICIES="$(iam_query "policies" scw iam policy list organization-id="${ORG_ID}" -o json)"
GROUPLIST="$(iam_query "groups" scw iam group list organization-id="${ORG_ID}" -o json)"
# API keys must be listed via the REST API: `scw iam api-key list` omits
# application_id, so app-owned keys could never be matched.
KEYLIST="$(iam_query "api-keys" curl -s -H "X-Auth-Token: ${SCW_SECRET_KEY}" \
  "https://api.scaleway.com/iam/v1alpha1/api-keys?organization_id=${ORG_ID}&per_page=100" \
  | jq -c '.api_keys // []' 2>/dev/null || echo '[]')"
SSHKEYS="$(iam_query "ssh-keys" scw iam ssh-key list organization-id="${ORG_ID}" -o json)"

# Keys belonging to the env's apps. `.application_id` must be bound first:
# jq's index() evaluates against the current input (the $ids array), so
# index(.application_id) directly errors.
KEYS="$(jq -c --argjson ids "${APPIDS}" \
  '[.[] | select((.application_id // "") != "") |
        select(.application_id as $aid | ($ids | index($aid)) != null)]' <<< "${KEYLIST}")"

PURGE_POLICIES="$(jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat))]' <<< "${POLICIES}")"
PURGE_GROUPS="$(jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat))]' <<< "${GROUPLIST}")"
PURGE_APPS="$(jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat))]' <<< "${APPLIST}")"
PURGE_SSH="$(jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat))]' <<< "${SSHKEYS}")"

c_policies="$(jq 'length' <<< "${PURGE_POLICIES}")"
c_groups="$(jq 'length' <<< "${PURGE_GROUPS}")"
c_keys="$(jq 'length' <<< "${KEYS}")"
c_apps="$(jq 'length' <<< "${PURGE_APPS}")"
c_ssh="$(jq 'length' <<< "${PURGE_SSH}")"
total=$((c_policies + c_groups + c_keys + c_apps + c_ssh))

echo "IAM leftovers  : ${total}  (prefix \"${PREFIX}\")"
[[ "${c_policies}" -gt 0 ]] && echo "  policies    : ${c_policies}" && jq -r '.[] | "    policy     \(.name)\t\(.id)"' <<< "${PURGE_POLICIES}"
[[ "${c_apps}"    -gt 0 ]] && echo "  applications: ${c_apps}"    && jq -r '.[] | "    app        \(.name)\t\(.id)"' <<< "${PURGE_APPS}"
[[ "${c_keys}"    -gt 0 ]] && echo "  api keys    : ${c_keys}"    && jq -r '.[] | "    api-key    \(.access_key)\t(app \(.application_id))"' <<< "${KEYS}"
[[ "${c_groups}"  -gt 0 ]] && echo "  groups      : ${c_groups}"  && jq -r '.[] | "    group      \(.name)\t\(.id)"' <<< "${PURGE_GROUPS}"
[[ "${c_ssh}"     -gt 0 ]] && echo "  ssh keys    : ${c_ssh}"     && jq -r '.[] | "    ssh-key    \(.name)\t\(.id)"' <<< "${PURGE_SSH}"

if [[ "${total}" -eq 0 ]]; then
  if [[ "${DISCOVERY_FAILED}" -eq 1 ]]; then
    echo "Nothing found, but some IAM discovery queries FAILED - refusing to report clean." >&2
    echo "Check .creds / org access and re-run (work item #2)." >&2
    exit 1
  fi
  echo "Nothing to purge - already clean."
  exit 0
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo "(dry run - not deleted.)"
  exit 0
fi

# -- Confirm ----------------------------------------------------------------
if [[ "${ASSUME_YES}" -ne 1 ]]; then
  read -r -p "Type the environment name (${ENV_NAME}) to confirm deletion of these ${total} IAM resource(s): " confirm
  if [[ "${confirm}" != "${ENV_NAME}" ]]; then
    echo "Aborted (confirmation did not match)."
    exit 1
  fi
fi

# -- Purge ------------------------------------------------------------------
# Order matters: policies/groups reference applications; keys before their
# apps (deleting an app removes leftover keys); SSH keys last.
purged=0
failed=0

purge_list() {  # <label> <cmd-prefix> <json> ; row id = resource id, name = display
  local label="$1" cmd="$2" json="$3" id name
  while IFS=$'\t' read -r id name; do
    [[ -z "${id}" ]] && continue
    echo "==> deleting ${label} ${name} (${id})"
    if ${cmd} "${id}" >/dev/null 2>&1; then
      purged=$((purged+1))
    else
      echo "    [FAIL] ${label} ${id}" >&2
      failed=$((failed+1))
    fi
  done < <(jq -r '.[] | "\(.id)\t\(.name)"' <<< "${json}")
}

purge_list "policy"     "scw iam policy delete"     "${PURGE_POLICIES}"
purge_list "group"      "scw iam group delete"      "${PURGE_GROUPS}"
# API keys: the row id is the access_key (name column carries the app id).
while IFS=$'\t' read -r access_key appid; do
  [[ -z "${access_key}" ]] && continue
  echo "==> deleting api-key ${access_key} (app ${appid})"
  if scw iam api-key delete "${access_key}" >/dev/null 2>&1; then
    purged=$((purged+1))
  else
    echo "    [FAIL] api-key ${access_key}" >&2
    failed=$((failed+1))
  fi
done < <(jq -r '.[] | "\(.access_key)\t\(.application_id)"' <<< "${KEYS}")
purge_list "application" "scw iam application delete" "${PURGE_APPS}"
purge_list "ssh-key"    "scw iam ssh-key delete"    "${PURGE_SSH}"

echo ""
echo "Purged ${purged} leftover IAM resource(s); ${failed} failed."

# -- Verify ----------------------------------------------------------------
REMAIN="$(scw iam application list organization-id="${ORG_ID}" -o json 2>/dev/null \
  | jq -c --arg pat "${PREFIX}" '[.[] | select(.name | test($pat))]' | jq 'length')"
echo "Remaining env-scoped applications: ${REMAIN}"
