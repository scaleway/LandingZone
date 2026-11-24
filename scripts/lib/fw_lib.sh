# ---------------------------------------------------------------------------
# scripts/lib/fw_lib.sh -- shared firewall SSH probing helpers.
#
# Consumed by the stage-3 probe scripts
# (providers/opnsense/probe-fw-passive.sh / probe-fw-active.sh).
# Single definition of the SSH options used to reach the throwaway firewall
# nodes through the PAT door (no host-key checking, short fail-fast timeout).
#
# Params are env-overridable so the scripts stay free of hardcoded endpoints
# (DOOR / PORT / FWKEY / FW_ACTIVE_LAN / FW_CONNECT_TIMEOUT).
# Sourced file, no shebang.
# shellcheck shell=bash
# ---------------------------------------------------------------------------

# Firewall SSH key: env override, else the gitignored per-env default.
FWKEY="${FWKEY:-}"
if [[ -z "${FWKEY}" ]]; then
  if [[ -n "${REPO_ROOT:-}" ]]; then
    FWKEY="${REPO_ROOT}/scw-lz/keys-dev/admin_key"
  else
    FWKEY="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scw-lz/keys-dev/admin_key"
  fi
fi

# shared ssh options for firewall nodes (same options as the test battery)
fw_ssh_opts=(
  -i "${FWKEY}"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout="${FW_CONNECT_TIMEOUT:-13}"
)

# fw_ssh <door-host> <port> <user> [remote-command...]
fw_ssh() {
  local door="$1" port="$2" user="$3"; shift 3
  ssh "${fw_ssh_opts[@]}" -p "${port}" "${user}@${door}" "$@"
}
