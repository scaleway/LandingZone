#!/bin/bash
# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Empty + delete an S3 bucket.
#
# Usage:
#   ./scripts/delete_s3.sh <bucket-name> [ENV] [-y] [--empty-only] [--creds <identity>] [--region <region>]
#
#   <bucket-name>  the bucket to destroy (e.g. lz-dev-image-import)
#   [ENV]          environment for the creds file (default: $ENV, then dev)
#   -y             skip the confirmation prompt (dangerous)
#   --empty-only   only delete objects/versions/delete-markers - keep the
#                  bucket so a terraform destroy can delete it cleanly itself
#   --creds <id>   creds identity: "lz-<env>" (default) or
#                  "lz-<env>-infra-ops" for the infra-ops state bucket
#   --region <r>   bucket region (default: $REGION, then fr-par). The DR
#                  backup bucket lives in the DR region (e.g. nl-ams).
#
# Deletes current objects, then versioned objects + delete-markers, then the
# bucket itself.
#
# Object-LOCKED buckets (the terraform state bucket is GOVERNANCE-locked for
# 365d): prior versions are protected, so every delete carries
# --bypass-governance-retention - without it a full destroy can never finish.
# Raw S3 follows the key's DEFAULT project, so only the infra-ops bootstrap
# key (default project = infra-ops) can empty the state bucket: use
# --creds lz-<env>-infra-ops for it, a plain lz-<env> key otherwise.
#
# Credentials come from the env (SCW_ACCESS_KEY / SCW_SECRET_KEY) or from
# .creds/lz-<ENV>.env (same loader apply/destroy use).
#
# Note: bucket names stay reserved in Scaleway's S3 backend for a while after
# deletion (GC) - recreating the same name too fast fails with
# BucketAlreadyExists.
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # REPO_ROOT is read by lib/stages.sh load_env_creds after sourcing
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUCKET_NAME="${1:-}"
if [[ -z "${BUCKET_NAME}" ]]; then
  echo "Usage: $0 <bucket-name> [ENV] [-y] [--creds <identity>] [--region <region>]" >&2
  exit 1
fi

ENV_NAME="${2:-${ENV:-dev}}"
ASSUME_YES=0
EMPTY_ONLY=0
CREDS_IDENTITY=""
REGION_ARG=""
# Parse optional --creds/--region/--empty-only out of the arg list; ENV stays as $2.
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --creds) CREDS_IDENTITY="$2"; shift 2 ;;
    --region) REGION_ARG="$2"; shift 2 ;;
    --empty-only) EMPTY_ONLY=1; shift ;;
    -y)      ASSUME_YES=1; shift ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done
BUCKET_NAME="${ARGS[0]:-${BUCKET_NAME}}"
ENV_NAME="${ARGS[1]:-${ENV_NAME}}"

# -- Credentials ------------------------------------------------------------
source "${SCRIPT_DIR}/lib/stages.sh"
# An explicit --creds is a hard instruction: otherwise load_env_creds keeps
# a user-exported SCW_ACCESS_KEY and could silently run with the wrong key.
# Unset the inherited vars so the file truly takes over.
if [[ -n "${CREDS_IDENTITY:-}" ]]; then
  unset SCW_ACCESS_KEY SCW_SECRET_KEY SCW_DEFAULT_PROJECT_ID SCW_DEFAULT_ORGANIZATION_ID
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
fi
load_env_creds "${CREDS_IDENTITY:-lz-${ENV_NAME}}"

REGION="${REGION_ARG:-${REGION:-fr-par}}"
ENDPOINT="https://s3.${REGION}.scw.cloud"

# aws CLI reads AWS_* vars; map our SCW_* credentials onto them.
export AWS_ACCESS_KEY_ID="${SCW_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SCW_SECRET_KEY}"
export AWS_DEFAULT_REGION="${REGION}"

# head-bucket succeeds only when the bucket exists AND this key can see it:
# 404 = already gone (nothing to do), 403/AccessDenied = wrong key - abort.
bucket_reachable() {
  aws s3api head-bucket --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" >/dev/null 2>&1
}

# Self-healing: the creds file (itself a terraform local_file) may be gone or
# stale after a partial teardown; recover the key pair from the backend
# snippet bootstrap embeds in its own tfstate backup (survives every teardown
# step). Each candidate is verified against the bucket - some backups hold a
# since-revoked key.
if ! bucket_reachable; then
  for _backup in "${REPO_ROOT}/scw-lz/envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate.backup" \
                 "${REPO_ROOT}"/scw-lz/envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate.*.backup; do
    [[ -f "${_backup}" ]] || continue
    # The backend snippet is stored as one JSON string; extract AK/SK from it.
    _block="$(awk '/Remote State Backend Configuration/,/skip_metadata_api_check/' "${_backup}" 2>/dev/null)"
    _ak="$(printf '%s' "${_block}" | grep -oE 'SCW[A-Z0-9]{14,}' | head -1 || true)"
    _sk="$(printf '%s' "${_block}" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | head -1 || true)"
    [[ -n "${_ak}" && -n "${_sk}" ]] || continue
    if AWS_ACCESS_KEY_ID="${_ak}" AWS_SECRET_ACCESS_KEY="${_sk}" \
         aws s3api head-bucket --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" >/dev/null 2>&1; then
      echo "  !! loaded creds could not reach bucket - recovered working key from ${_backup}"
      SCW_ACCESS_KEY="${_ak}"; SCW_SECRET_KEY="${_sk}"
      export AWS_ACCESS_KEY_ID="${_ak}" AWS_SECRET_ACCESS_KEY="${_sk}"
      break
    else
      echo "  !! backup ${_backup} holds a non-working key - skipping" >&2
    fi
  done
fi

if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" ]]; then
  echo "error: SCW_ACCESS_KEY and SCW_SECRET_KEY are not set (and no working key" >&2
  echo "       could be recovered from scw-lz/envs/${ENV_NAME}/bootstrap-*.tfstate.*backup)." >&2
  echo "       Fill .creds/lz-${ENV_NAME}.env (or --creds lz-${ENV_NAME}-infra-ops) or export them." >&2
  exit 1
fi

if [[ "${ASSUME_YES}" -ne 1 ]]; then
  if [[ "${EMPTY_ONLY}" -eq 1 ]]; then
    echo "You are about to EMPTY the bucket '${BUCKET_NAME}' in ${REGION} (objects removed, bucket kept - irreversible)."
  else
    echo "You are about to DELETE the bucket '${BUCKET_NAME}' in ${REGION} (irreversible)."
  fi
  read -r -p "Type the bucket name to confirm: " confirm
  if [[ "${confirm}" != "${BUCKET_NAME}" ]]; then
    echo "Aborted (confirmation did not match)."
    exit 1
  fi
fi

# 404/NoSuchBucket = already gone, nothing to do; 403/AccessDenied = wrong
# key, must abort (silently reporting success here is how the infra-ops
# project got orphaned). Use `if !` - under set -e an assignment would die
# before this branch can decide anything.
if ! bucket_reachable; then
  _hb_err="$(aws s3api head-bucket --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" 2>&1 || true)"
  if [[ "${_hb_err}" == *"403"* || "${_hb_err}" == *"AccessDenied"* || "${_hb_err}" == *"Forbidden"* ]]; then
    echo "error: the loaded key cannot access bucket '${BUCKET_NAME}' (AccessDenied)." >&2
    echo "       A bucket in the infra-ops project needs the bootstrap key - pass" >&2
    echo "       --creds lz-${ENV_NAME}-infra-ops (or restore .creds/lz-${ENV_NAME}-infra-ops.env)." >&2
    exit 1
  fi
  echo "Bucket '${BUCKET_NAME}' not found - nothing to do."
  exit 0
fi

echo "==> Emptying bucket: ${BUCKET_NAME}"
# --bypass-governance-retention is not supported on `aws s3 rm` (AWS CLI >=
# 2.27); it goes on the s3api delete-object calls below. s3 rm on a locked
# current version is allowed (creates a delete marker); the version pass
# purges the locked versions.
aws s3 rm "s3://${BUCKET_NAME}" --recursive --endpoint-url "${ENDPOINT}"

echo "==> Deleting versioned objects / delete markers"
VERSIONS=$(aws s3api list-object-versions --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" --output json 2>/dev/null || echo "{}")

# Locked buckets need --bypass-governance-retention; plain buckets reject it
# ("only applicable to Object Lock enabled buckets") - retry without it.
delete_object_version() {
  local key="$1" ver="$2" out
  if out="$(aws s3api delete-object \
      --bucket "${BUCKET_NAME}" \
      --key "${key}" \
      --version-id "${ver}" \
      --bypass-governance-retention \
      --endpoint-url "${ENDPOINT}" 2>&1)"; then
    return 0
  fi
  if [[ "${out}" == *"only applicable to Object Lock enabled buckets"* ]]; then
    aws s3api delete-object \
      --bucket "${BUCKET_NAME}" \
      --key "${key}" \
      --version-id "${ver}" \
      --endpoint-url "${ENDPOINT}" >/dev/null
    return 0
  fi
  echo "error: could not delete ${key} v${ver}: ${out}" >&2
  return 1
}

_delete_failures=0
while IFS=' ' read -r key version; do
  [[ -n "${key}" ]] || continue
  delete_object_version "${key}" "${version}" || _delete_failures=$((_delete_failures + 1))
done < <(echo "${VERSIONS}" | jq -r '.Versions[]? | "\(.Key) \(.VersionId)"')

while IFS=' ' read -r key version; do
  [[ -n "${key}" ]] || continue
  delete_object_version "${key}" "${version}" || _delete_failures=$((_delete_failures + 1))
done < <(echo "${VERSIONS}" | jq -r '.DeleteMarkers[]? | "\(.Key) \(.VersionId)"')

if [[ "${_delete_failures}" -gt 0 ]]; then
  echo "error: ${_delete_failures} object version(s) could not be deleted; bucket left in place." >&2
  echo "       Re-run the destroy once the transient S3 condition clears." >&2
  exit 1
fi

if [[ "${EMPTY_ONLY}" -eq 1 ]]; then
  echo "Bucket '${BUCKET_NAME}' emptied (kept in place for terraform destroy)."
  exit 0
fi

echo "==> Deleting bucket: ${BUCKET_NAME}"
# delete-bucket right after a big purge fails transiently (eventual
# consistency / "bucket not empty" lag). Retry; only claim success once the
# bucket is verifiably gone, and exit non-zero so destroy.sh aborts before
# anything else is destroyed.
_bucket_deleted=0
for _try in 1 2 3 4 5; do
  if aws s3api delete-bucket --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" >/dev/null 2>&1; then
    # Confirm it is really gone (head-bucket must now fail).
    if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" --endpoint-url "${ENDPOINT}" >/dev/null 2>&1; then
      _bucket_deleted=1
      break
    fi
  fi
  echo "  !! delete-bucket attempt ${_try}/5 did not complete - retrying in 3s..."
  sleep 3
done
if [[ "${_bucket_deleted}" -ne 1 ]]; then
  echo "error: bucket '${BUCKET_NAME}' could not be deleted after 5 attempts." >&2
  echo "       It still exists and would block the infra-ops project destroy; aborting." >&2
  exit 1
fi
echo "Bucket '${BUCKET_NAME}' deleted successfully."
