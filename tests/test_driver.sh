#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# tests/test_driver.sh -- offline regression for the unified CLI driver
# (scripts/apply.sh + scripts/destroy.sh + scripts/lib/stages.sh) against a
# fake terraform (tests/bin/terraform). No cloud, no network, no credentials.
#
# Creates a throwaway env (scw-lz/envs/__harness__) seeded with empty tfvars,
# runs the driver, asserts stage ordering / filtering / flag handling, then
# removes the env. Run standalone or via tests/run-tests.sh (`make test`).
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

ENV_NAME="__harness__"
ENV_DIR="scw-lz/envs/${ENV_NAME}"
TF_LOG="$(mktemp).log"
OUT="$(mktemp)"
export TF_LOG
export PATH="${SCRIPT_DIR}/bin:$PATH"   # fake terraform takes over
export SCW_ACCESS_KEY=fake SCW_SECRET_KEY=fake ORG_ID=fake-org

FAILS=0
pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAILS=$((FAILS+1)); }

cleanup() { rm -rf "${ENV_DIR}" "${TF_LOG}" "${OUT}"; }
trap cleanup EXIT

# --- seed the throwaway env with every tfvars the registry expects ---------
STAGES=(1-security 2-networking 3-security-appliances 4-project-factory 6-interconnection 5-backup)
mkdir -p "${ENV_DIR}"
for f in backend providers remote_state "${STAGES[@]}"; do
  : > "${ENV_DIR}/${f}-${ENV_NAME}.tfvars"
done

# banners <outfile> -> stage labels in run order, one per line
banners() {
  grep -oE '== (bootstrap|stage-[0-9]): (apply|plan \(dry-run\)|destroy) ==' "$1" \
    | sed -E 's/== (.*): .* ==/\1/'
}

# check_seq <outfile> <label> <expected labels...>
check_seq() {
  local out="$1" label="$2"; shift 2
  local got expected="$*"
  got="$(banners "$out" | tr '\n' ' ' | sed 's/ $//')"
  if [ "$got" = "$expected" ]; then
    pass "$label"
  else
    fail "$label (got: '$got', want: '$expected')"
  fi
}

# Stage-4 (project factory) is DISABLED by default: apply/destroy only run it
# when the per-env demo tfvars (4-project-factory-<env>-demo.tfvars) exist.
# The default seeded env (below) has only the plain template, so the default
# chains omit stage-4; the "stage-4 enabled" case is covered at the end.
DEFAULT_FWD="bootstrap stage-1 stage-2 stage-3 stage-5 stage-6"
DEFAULT_REV="stage-6 stage-5 stage-3 stage-2 stage-1 bootstrap"
WITH_S4_FWD="bootstrap stage-1 stage-2 stage-3 stage-4 stage-5 stage-6"
WITH_S4_REV="stage-6 stage-5 stage-4 stage-3 stage-2 stage-1 bootstrap"

# 1. full apply: all stages in forward order (stage-4 skipped by default)
./scripts/apply.sh "${ENV_NAME}" >"$OUT" 2>&1
check_seq "$OUT" "apply: full chain in forward order (stage-4 skipped by default)" $DEFAULT_FWD

# 2. plan with --skip-bootstrap: no bootstrap, dry-run banner (stage-4 still skipped)
./scripts/apply.sh "${ENV_NAME}" --skip-bootstrap --plan >"$OUT" 2>&1
check_seq "$OUT" "apply --skip-bootstrap --plan: no bootstrap" \
  stage-1 stage-2 stage-3 stage-5 stage-6
grep -q 'plan (dry-run)' "$OUT" \
  && pass "plan mode bannered as dry-run" \
  || fail "plan not bannered as dry-run"

# 3. destroy DEFAULT: workload stages only (2-6) - stage-1 + bootstrap kept
./scripts/destroy.sh "${ENV_NAME}" >"$OUT" 2>&1
check_seq "$OUT" "destroy: workloads only, stage-4 skipped (stage-1 + bootstrap kept)" \
  stage-6 stage-5 stage-3 stage-2
grep -q '== stage-1: destroy ==' "$OUT" \
  && fail "destroy default: stage-1 still ran (foundation should be kept)" \
  || pass "destroy default: stage-1 kept"
grep -q '== bootstrap: destroy ==' "$OUT" \
  && fail "destroy default: bootstrap still ran (foundation should be kept)" \
  || pass "destroy default: bootstrap kept"

# 4. destroy --everything: full chain in reverse order (bootstrap last), stage-4
#    skipped unless its demo tfvars exist
./scripts/destroy.sh "${ENV_NAME}" --everything >"$OUT" 2>&1
check_seq "$OUT" "destroy --everything: full chain in reverse order (stage-4 skipped)" $DEFAULT_REV

# 4. --stage filter: only the requested stage runs
./scripts/apply.sh "${ENV_NAME}" --skip-bootstrap --stage 3 --plan >"$OUT" 2>&1
check_seq "$OUT" "--stage 3: only stage-3" stage-3

# 5. unknown stage -> clean error, non-zero exit
if ./scripts/apply.sh "${ENV_NAME}" --stage 9 >"$OUT" 2>&1; then
  fail "--stage 9: expected non-zero exit"
else
  grep -q 'unknown stage: 9' "$OUT" \
    && pass "--stage 9: rejected with clear error" \
    || fail "--stage 9: wrong error message"
fi

# 6. --plan rejected on destroy
if ./scripts/destroy.sh "${ENV_NAME}" --plan >"$OUT" 2>&1; then
  fail "destroy --plan: expected rejection"
else
  grep -q -- '--plan is only valid with apply' "$OUT" \
    && pass "destroy --plan: rejected" \
    || fail "destroy --plan: wrong error message"
fi

# 7. ENV= fallback (no positional): resolves to the right env, not "dev"
if ENV="${ENV_NAME}" ./scripts/apply.sh --skip-bootstrap --plan >"$OUT" 2>&1; then
  grep -q "environment : ${ENV_NAME}" "$OUT" \
    && pass "ENV= fallback: resolves to ${ENV_NAME}" \
    || fail "ENV= fallback: wrong environment in output"
else
  fail "ENV= fallback: run failed"
fi

# 8. destroy --everything --skip-bootstrap: bootstrap must NOT run
./scripts/destroy.sh "${ENV_NAME}" --everything --skip-bootstrap >"$OUT" 2>&1
grep -q '== bootstrap: destroy ==' "$OUT" \
  && fail "destroy --skip-bootstrap: bootstrap still ran" \
  || pass "destroy --skip-bootstrap: bootstrap skipped"

# 9. stage-4 ENABLED: once the demo tfvars exist, apply includes stage-4 in the
#    chain. Seed the demo tfvars, re-run apply, then remove it.
: > "${ENV_DIR}/4-project-factory-${ENV_NAME}-demo.tfvars"
./scripts/apply.sh "${ENV_NAME}" >"$OUT" 2>&1
check_seq "$OUT" "apply: stage-4 included once demo tfvars present" $WITH_S4_FWD
rm -f "${ENV_DIR}/4-project-factory-${ENV_NAME}-demo.tfvars"

if [ "$FAILS" -eq 0 ]; then
  echo "DRIVER TESTS ALL PASSED"
  exit 0
else
  echo "DRIVER TESTS FAILED: ${FAILS}"
  exit 1
fi
