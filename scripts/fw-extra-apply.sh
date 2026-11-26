#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/fw-extra-apply.sh - hot-apply a #cloud-config payload to a firewall
# node through the hub door PAT (no instance rebuild, no FW reboot).
#
# Hash-idempotent: renders the payload with fw-extra-render.py into a remote
# sh script whose final action records <hash> at /conf/.extra_uud_<node>.hash.
# If the remote marker already matches the new hash the apply is skipped
# (content-unchanged => no-op). The marker is written only after every step
# succeeds (remote script uses `set -e`), so a failed apply is retried on the
# next run instead of being falsely marked done.
#
# Consumption contract (partner):
#   key "cloud-init", format "#cloud-config", minimum runcmd + write_files,
#   executed only when the content changes.
#
# Usage (invoked by stage-3 null_resources via local-exec):
#   FW_CI_FILE=<payload-path> FW_NODE=active|passive DOOR=<ip> FW_PORT=<8023|8022> \
#     ./scripts/fw-extra-apply.sh
#
# Env:
#   FW_CI_FILE  path to the #cloud-config payload (required; empty => no-op)
#   FW_NODE     active | passive (required; selects marker file + default port)
#   DOOR        hub door IP (required)
#   FW_PORT     door PAT port (default: 8023 active / 8022 passive)
#   FWKEY       ssh key (default via fw_lib: scw-lz/keys-<env>/admin_key)
#   FW_CI_HASH  hash to record as the remote marker (optional; defaults to
#               sha256 of the payload so null_resource triggers and the node
#               marker never drift apart)
#   FW_APPLY_TRIES / FW_APPLY_WAIT  ssh readiness retry budget (default 20/15)
# ---------------------------------------------------------------------------
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/lib/fw_lib.sh"

FW_CI_FILE="${FW_CI_FILE:-}"
FW_NODE="${FW_NODE:-}"
DOOR="${DOOR:-}"

if [[ -z "${FW_CI_FILE}" || ! -s "${FW_CI_FILE}" ]]; then
  echo "fw-extra-apply: no payload (FW_CI_FILE empty/missing) - nothing to apply."
  exit 0
fi
[[ -n "${FW_NODE}" ]] || { echo "fw-extra-apply: FW_NODE required (active|passive)" >&2; exit 1; }
[[ -n "${DOOR}" ]] || { echo "fw-extra-apply: DOOR required" >&2; exit 1; }

case "${FW_NODE}" in
  active)  FW_PORT="${FW_PORT:-8023}" ;;
  passive) FW_PORT="${FW_PORT:-8022}" ;;
  *) echo "fw-extra-apply: FW_NODE must be active|passive (got ${FW_NODE})" >&2; exit 1 ;;
esac

# Stable content hash: explicit override wins (Terraform passes the same value
# it uses for null_resource.triggers), else sha256 of the payload file.
if [[ -n "${FW_CI_HASH:-}" ]]; then
  HASH="${FW_CI_HASH}"
else
  HASH="$(shasum -a 256 "${FW_CI_FILE}" | awk '{print $1}')"
fi

MARK_REMOTE="/conf/.extra_uud_${FW_NODE}.hash"
SCRIPT_REMOTE="/tmp/fw-extra-${FW_NODE}.sh"

# Remote login shell on OPNsense is csh, which rejects POSIX redirection
# (`2>&1` / `2>/dev/null` -> "Ambiguous output redirect"). Every remote
# command is therefore executed by /bin/sh. Careful quoting: ssh flattens its
# argv into one string and the remote csh re-parses it, so the /bin/sh -c
# argument is wrapped in LITERAL double quotes (they must survive both the
# local shell and the remote csh) to keep the pipeline intact.
ssh_run() { # ssh_run <remote-command-string>
  ssh "${fw_ssh_opts[@]}" -p "${FW_PORT}" "root@${DOOR}" /bin/sh -c "\"$1\""
}

# --- 0. wait for the door ssh to accept connections -------------------------
tries="${FW_APPLY_TRIES:-20}"
wait_s="${FW_APPLY_WAIT:-15}"
ready=0
for ((i = 1; i <= tries; i++)); do
  if ssh_run 'echo door-ok' >/dev/null 2>&1; then
    ready=1
    break
  fi
  echo "fw-extra-apply: door not ready (${i}/${tries}), retrying in ${wait_s}s..."
  sleep "${wait_s}"
done
if [[ "${ready}" -ne 1 ]]; then
  echo "fw-extra-apply: FATAL - door ${DOOR}:${FW_PORT} never became reachable" >&2
  exit 1
fi

# --- 1. idempotency: skip when the node already has this content ------------
old="$(ssh_run "cat ${MARK_REMOTE} 2>/dev/null" 2>/dev/null | tail -1)"
if [[ "${old}" == "${HASH}" ]]; then
  echo "fw-extra-apply: ${FW_NODE} already at ${HASH} - no apply needed"
  exit 0
fi
echo "fw-extra-apply: ${FW_NODE} marker ${old:-<none>} != ${HASH} - applying"

# --- 2. render the remote apply script --------------------------------------
CI_B64="$(cat "${FW_CI_FILE}" | base64 | tr -d '\n')"
RENDERED="$(mktemp /tmp/fw-extra-render.XXXXXX)"
trap 'rm -f "${RENDERED}"' EXIT
if ! FW_CI_B64="${CI_B64}" FW_NODE="${FW_NODE}" FW_HASH="${HASH}" \
    python3 "${REPO_ROOT}/scripts/fw-extra-render.py" > "${RENDERED}"; then
  echo "fw-extra-apply: render failed (payload not a supported #cloud-config?)" >&2
  exit 1
fi
if ! /bin/sh -n "${RENDERED}"; then
  echo "fw-extra-apply: rendered script failed syntax check" >&2
  exit 1
fi

# --- 3. ship + run -----------------------------------------------------------
if ! scp "${fw_ssh_opts[@]}" -P "${FW_PORT}" "${RENDERED}" "root@${DOOR}:${SCRIPT_REMOTE}"; then
  echo "fw-extra-apply: scp to ${DOOR}:${FW_PORT} failed" >&2
  exit 1
fi

if ! out="$(ssh_run "/bin/sh ${SCRIPT_REMOTE} && echo APPLY_RC_OK")"; then
  echo "fw-extra-apply: remote execution failed" >&2
  echo "${out}" | tail -20 >&2
  exit 1
fi

# --- 4. verify the marker landed ---------------------------------------------
now="$(ssh_run "cat ${MARK_REMOTE} 2>/dev/null" 2>/dev/null | tail -1)"
if [[ "${now}" != "${HASH}" ]]; then
  echo "fw-extra-apply: marker verification failed (got ${now:-<none>})" >&2
  exit 1
fi
echo "fw-extra-apply: ${FW_NODE} applied (${HASH}) - marker verified"
