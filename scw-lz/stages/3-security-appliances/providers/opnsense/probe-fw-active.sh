#!/usr/bin/env bash
# Probe fw-active state via fw-passive jump. No args.
# Endpoints: live addresses are env-provided; blueprint layout keeps defaults.
#   DOOR           hub PGW / PAT door IP (required, e.g. from test-firewalls.env)
#   PORT           fw-passive ssh door port (default 8022)
#   FW_ACTIVE_LAN  fw-active LAN IP (blueprint default 10.10.0.12, env-overridable)
#   FWKEY          firewall SSH key path (via fw_lib: env or scw-lz/keys-dev/admin_key)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
source "${REPO_ROOT}/scripts/lib/fw_lib.sh"

: "${DOOR:?DOOR must be set - hub PGW / PAT door IP (export DOOR=<public-ip>)}"
PORT="${PORT:-8022}"
FW_ACTIVE_LAN="${FW_ACTIVE_LAN:-10.10.0.12}"

# Inner ssh (run ON the door host) to reach fw-active's LAN IP.
ROOT_INNER=(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 "root@${FW_ACTIVE_LAN}")

fw_ssh "${DOOR}" "${PORT}" root \
  "${ROOT_INNER[*]} hostname; ${ROOT_INNER[*]} uptime; ${ROOT_INNER[*]} ifconfig -a; ${ROOT_INNER[*]} netstat -rn; ${ROOT_INNER[*]} cat /etc/hostname" \
  2>&1 | tail -70
