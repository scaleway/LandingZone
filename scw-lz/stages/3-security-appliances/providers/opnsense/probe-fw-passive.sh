#!/usr/bin/env bash
# Probe fw-passive interfaces + CARP + reachability to fw-active (via fw-passive jump).
# Endpoints: live addresses are env-provided; blueprint layout keeps defaults.
#   DOOR        hub PGW / PAT door IP (required, e.g. from test-firewalls.env)
#   PORT        fw-passive ssh door port (default 8022)
#   FW_ACTIVE_LAN  fw-active LAN IP (blueprint default 10.10.0.12, env-overridable)
#   FWKEY       firewall SSH key path (via fw_lib: env or scw-lz/keys-dev/admin_key)
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
source "${REPO_ROOT}/scripts/lib/fw_lib.sh"

: "${DOOR:?DOOR must be set - hub PGW / PAT door IP (export DOOR=<public-ip>)}"
PORT="${PORT:-8022}"
FW_ACTIVE_LAN="${FW_ACTIVE_LAN:-10.10.0.12}"

echo "===== fw-passive: interfaces ====="
fw_ssh "${DOOR}" "${PORT}" root 'ifconfig -a' 2>&1 | grep -E '^[a-z0-9]+:|inet ' | head -50
echo "===== fw-passive: CARP status ====="
fw_ssh "${DOOR}" "${PORT}" root 'ifconfig carp0; ifconfig carp1' 2>&1 | grep -E 'carp|inet |MASTER|BACKUP' | head -20
echo "===== fw-passive: routing ====="
fw_ssh "${DOOR}" "${PORT}" root 'netstat -rn' 2>&1 | grep -E 'default|10\.10\.0\.|Destination' | head -12
echo "===== fw-passive: can reach fw-active lan (ping + sshd)? ====="
fw_ssh "${DOOR}" "${PORT}" root "ping -c2 -W2 ${FW_ACTIVE_LAN}" 2>&1 | tail -3
fw_ssh "${DOOR}" "${PORT}" root "nc -z -w3 ${FW_ACTIVE_LAN} 22; echo nc_exit=\$?" 2>&1 | tail -3
