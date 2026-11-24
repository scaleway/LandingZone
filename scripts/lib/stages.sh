# ---------------------------------------------------------------------------
# scripts/lib/stages.sh -- shared stage registry + terraform driver.
#
# Single source of truth for the Landing Zone Toolkit orchestration:
#   - the ordered stage list (apply forward, destroy reverse)
#   - per-stage dir + how it is initialised / which var-files it consumes
#   - the unified `run_stage apply|plan|destroy <key>` driver and the
#     `resolve_stage <alias>` helper for --stage filtering
#
# Sourced by scripts/apply.sh and scripts/destroy.sh. Sourced file, no shebang.
# shellcheck shell=bash
# shellcheck disable=SC2034  # STAGES_FORWARD is consumed by apply.sh/destroy.sh
#
# Expected globals (set by the sourcing script before calling run_stage):
#   REPO_ROOT        absolute path to the repo root
#   ENV_NAME         environment name (e.g. "dev")
#   ORG_ID, PROJECT_ID, REGION, ZONE
#   INFRA_OPS_PROJECT_NAME       (optional, bootstrap only)
#
# Per-env tfvars paths are relative to a stage dir (../../envs/...), which is
# terraform's cwd -- do NOT make them absolute.
# ---------------------------------------------------------------------------

# Ordered stage keys (apply order). Destroy iterates in reverse.
STAGES_FORWARD=(
  bootstrap
  1-security
  2-networking
  3-security-appliances
  4-project-factory
  5-backup
  6-interconnection
)

# stage_dir <key>  -> dir under scw-lz/ (bootstrap is the only special case)
stage_dir() {
  if [[ "$1" == "bootstrap" ]]; then
    printf '%s\n' "bootstrap"
  else
    printf 'stages/%s\n' "$1"
  fi
}

# stage_display <key> -> human label ("bootstrap", "stage-0", ...)
stage_display() {
  if [[ "$1" == "bootstrap" ]]; then
    printf '%s\n' "bootstrap"
  else
    printf 'stage-%s\n' "${1%%-*}"
  fi
}

# resolve_stage <alias> -> canonical registry key. Accepts the registry key
# ("3-security-appliances"), the bare number ("3"), or the Makefile-style
# stage-N alias ("stage-3"). Echoes the key and returns 0, or returns 1 if
# no stage matches.
resolve_stage() {
  local alias="$1" key
  alias="${alias#stage-}"
  for key in "${STAGES_FORWARD[@]}"; do
    if [[ "${key}" == "${alias}" || "${key%%-*}" == "${alias}" ]]; then
      printf '%s\n' "${key}"
      return 0
    fi
  done
  return 1
}

# envcfg <stem> -> relative path to envs/<ENV>/<stem>-<ENV>.tfvars
# (relative to any stage dir under scw-lz/, which is terraform's cwd).
# Prefers the live <stem>-<ENV>-demo.tfvars when present (real per-env data,
# gitignored); otherwise falls back to the committed <stem>-<ENV>.tfvars
# template - so public clones work straight from the templates.
envcfg() {
  # The -f test must use a REPO_ROOT-based path: envcfg is evaluated from the
  # script's cwd (repo root), while the printed path is relative to a stage dir
  # (terraform's cwd, ../../envs/...). Testing ../../envs from repo root would
  # always miss and fall back to the committed placeholder template.
  local stem="scw-lz/envs/${ENV_NAME}/${1}-${ENV_NAME}"
  if [[ -f "${REPO_ROOT}/${stem}-demo.tfvars" ]]; then
    printf '../../envs/%s/%s-%s-demo.tfvars' "${ENV_NAME}" "$1" "${ENV_NAME}"
  else
    printf '../../envs/%s/%s-%s.tfvars' "${ENV_NAME}" "$1" "${ENV_NAME}"
  fi
}

err() {
  echo "Error: $*" >&2
  exit 1
}

# require_creds -- fail fast with an explicit, actionable message when the
# Scaleway credentials are not present in the environment. Called by the
# apply/destroy drivers before ANY cloud interaction so an unset key can never
# silently half-run a stage.
#
# Usage (from scripts/apply.sh | scripts/destroy.sh):
#   require_creds
require_creds() {
  if [[ -z "${SCW_ACCESS_KEY:-}" || -z "${SCW_SECRET_KEY:-}" ]]; then
    cat >&2 <<'EOF'

error: SCW_ACCESS_KEY and SCW_SECRET_KEY are not set.
       Every apply/destroy run needs live Scaleway credentials.

Fix (pick one):

  A) Prepare the owner key once, then run bootstrap (the toolkit writes the
     per-env files):
       cp templates/creds/lz-creds.env .creds/lz-creds.env
       $EDITOR .creds/lz-creds.env      # fill in YOUR owner key
       make bootstrap   -> .creds/lz-<env>-infra-ops.env (bootstrap key)
                        -> .creds/lz-<env>.env           (lz deploy key)
     Then re-run. One key per project; the stage you run auto-loads the
     right file (bootstrap uses the infra-ops key, stages 1-6 the lz key).

  B) Or export your own credentials in this shell (replace placeholders):
       export SCW_ACCESS_KEY=SCWxxxxxxxxxxxxxxxx
       export SCW_SECRET_KEY=00000000-0000-0000-0000-000000000000
       export ORG_ID=<your-organization-id>

  C) CI/CD: mount the bootstrap SA key from the Secret Manager secret
     lz-<env>-bootstrap-credentials (access_key / secret_key fields).

Note: export ORG_ID too (or put it in the creds file) - it is required.
EOF
    exit 1
  fi
}

# creds_file_for <stage-key> -> path of the creds file for that stage.
# bootstrap is the DAY-0 ORIGIN: it CREATES every derived SA key (bootstrap
# SA + lz deploy SA, written to .creds/lz-<env>-infra-ops.env and
# .creds/lz-<env>.env), so it must ALWAYS run with the user's org-level owner
# key (.creds/lz-creds.env) - never with a previously generated SA key
# (circular dependency: once that key dies - orphan SA / self-brick - the
# stage can no longer recover on its own). Stages 1-6 run with the lz deploy
# key (created by bootstrap), default project = lz-<env>.
# Legacy single-file fallback .creds/<env>.env still works.
creds_file_for() {
  case "$1" in
    bootstrap)
      printf '%s\n' "${REPO_ROOT}/.creds/lz-creds.env"
      ;;
    *)
      printf '%s\n' "${REPO_ROOT}/.creds/lz-${ENV_NAME}.env"
      ;;
  esac
}

# load_env_creds [stage-key|identity] -- source the per-environment
# credentials file.
# Convention: "<repo>/.creds/lz-<ENV>.env" (lz deploy key, stages 1-6) or
# "<repo>/.creds/lz-<ENV>-infra-ops.env" (bootstrap key, bootstrap stage),
# falling back to the legacy "<repo>/.creds/<ENV_NAME>.env".
# The argument may be a stage key ("bootstrap", "3-security-appliances", ...)
# or a full identity ("lz-dev", "lz-dev-infra-ops") - both resolve to the
# same file.
# The bootstrap stage GENERATES these files for you (bootstrap writes BOTH the
# infra-ops key and the lz deploy key); you can also fill them by hand /
# override with your own keys. Same idea as "include .envrc", but
# per-environment so dev and prod never share a file.
#
# Rules:
#   - last-resort fallback: when no per-env file exists (fresh checkout before
#     the first bootstrap) the loader sources .creds/lz-creds.env - the
#     user-prepared ORG-LEVEL owner key (see
#     templates/creds/lz-creds.env). It is the day-0 identity;
#     bootstrap then generates the per-env files that take over.
#   - file is optional: no file, no-op (require_creds / ORG_ID guard handle it)
#   - a key you had ALREADY exported in your shell before the first load is
#     "user-provided" and is NEVER overwritten by any file (documented rule)
#   - a key loaded BY THIS LOADER can be switched by a later load, so every
#     stage gets its own project-scoped key in one full apply/destroy run
#     (bootstrap -> infra-ops key, stages 1-6 -> lz key)
#   - blank lines, "#" comments, and an optional "export " prefix are ignored
_user_exported_keys=""
_load_registered=0
load_env_creds() {
  local key_arg="${1:-}" f

  # First call: remember which identity keys the user exported up front.
  if [[ "${_load_registered}" -eq 0 ]]; then
    _load_registered=1
    for k in SCW_ACCESS_KEY SCW_SECRET_KEY ORG_ID REGION ZONE ENV; do
      [[ -n "${!k:-}" ]] && _user_exported_keys="${_user_exported_keys} ${k}"
    done
  fi

  case "${key_arg}" in
    lz-*) # full identity already (e.g. lz-dev, lz-dev-infra-ops)
      f="${REPO_ROOT}/.creds/${key_arg}.env" ;;
    *)
      f="$(creds_file_for "${key_arg}")"
      [[ -f "${f}" ]] || f="${REPO_ROOT}/.creds/${ENV_NAME}.env"
      # Last-resort fallback: the user-prepared ORG-LEVEL owner key (day-0).
      # Only reached on a fresh checkout before the first bootstrap - after
      # that the per-env files above exist and take precedence.
      [[ -f "${f}" ]] || f="${REPO_ROOT}/.creds/lz-creds.env"
      ;;
  esac
  [[ -f "${f}" ]] || return 0
  echo "credentials: loaded ${f}"
  local line key val
  while IFS= read -r line; do
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    # Tolerate the classic source-able "export KEY=value" form (bootstrap
    # writes .creds/*.env that way); strip the leading "export ".
    [[ "${key}" == "export "* ]] && key="${key#export }"
    key="${key%"${key##*[![:space:]]}"}"   # trim trailing spaces on the key
    [[ -z "${key}" ]] && continue
    # A genuinely user-exported key wins; everything else is (re)set so the
    # per-stage key split works across one full apply/destroy run.
    if [[ -n "${!key:-}" ]] && [[ " ${_user_exported_keys} " == *" ${key} "* ]]; then
      continue
    fi
    export "${key}=${val}"
  done < "${f}"

  # The owner key (.creds/lz-creds.env) carries the org as
  # SCW_DEFAULT_ORGANIZATION_ID, while the drivers require ORG_ID - derive it
  # when unset so a user-prepared owner key is enough for the first bootstrap.
  # An ORG_ID the user exported in the shell is never overridden.
  if [[ -z "${ORG_ID:-}" && -n "${SCW_DEFAULT_ORGANIZATION_ID:-}" ]]; then
    export ORG_ID="${SCW_DEFAULT_ORGANIZATION_ID}"
  fi
}

# parse_cli <base-action> [args...]
# Shared CLI parser for apply.sh / destroy.sh (single source of truth, so the
# two scripts cannot drift on flag handling). <base-action> is "apply" or
# "destroy". Accepts:
#   [ENVIRONMENT]      positional; falls back to $ENV, then "dev"
#   --skip-bootstrap   skip the bootstrap stage
#   --everything       destroy-only: also destroy the foundation (stage-1
#                      security baseline + bootstrap). Default keeps both - the
#                      "tear down the workloads" flow - so a full teardown is
#                      always an explicit, deliberate choice.
#   --stage <key>      run only one stage (alias/number/key, resolved + validated)
#   --plan             apply-only: dry-run instead of apply
# Sets globals: ENV_NAME, SKIP_BOOTSTRAP, INCLUDE_FOUNDATION, ACTION,
#               STAGE_ONLY (canonical key or "").
parse_cli() {
  local base="$1"; shift
  local _stage_input=""
  local _args=("$@") i arg
  ENV_NAME=""
  SKIP_BOOTSTRAP=false
  INCLUDE_FOUNDATION=false
  ACTION="${base}"
  STAGE_ONLY=""

  for ((i = 0; i < ${#_args[@]}; i++)); do
    arg="${_args[$i]}"
    case "${arg}" in
      --skip-bootstrap) SKIP_BOOTSTRAP=true ;;
      --everything)
        if [[ "${base}" != "destroy" ]]; then
          err "--everything is only valid with destroy (use ./scripts/destroy.sh --everything)"
        fi
        INCLUDE_FOUNDATION=true
        ;;
      --plan)
        if [[ "${base}" != "apply" ]]; then
          err "--plan is only valid with apply (use ./scripts/apply.sh --plan)"
        fi
        ACTION=plan
        ;;
      --stage)
        if [[ $((i + 1)) -ge ${#_args[@]} ]]; then
          err "--stage requires a value."
        fi
        STAGE_ONLY="${_args[$((i + 1))]}"
        i=$((i + 1))
        ;;
      --*) err "unknown argument: ${arg}" ;;
      *)
        if [[ -z "${ENV_NAME}" ]]; then
          ENV_NAME="${arg}"
        else
          err "unknown argument: ${arg}"
        fi
        ;;
    esac
  done

  if [[ -n "${STAGE_ONLY}" ]]; then
    _stage_input="${STAGE_ONLY}"
    if ! STAGE_ONLY="$(resolve_stage "${_stage_input}")"; then
      err "unknown stage: ${_stage_input} (want one of: ${STAGES_FORWARD[*]})"
    fi
  fi

  ENV_NAME="${ENV_NAME:-${ENV:-dev}}"
}

# run_stage <apply|plan|destroy> <key> [extra -var args...]
run_stage() {
  local action="$1" key="$2"; shift 2
  local extra_vars=("$@")
  local dir display back prov rstate stage_env_cfg iopn cfg_args pcfg img_cfg bcfg
  dir="$(stage_dir "${key}")"
  display="$(stage_display "${key}")"
  back="$(envcfg backend)"
  prov="$(envcfg providers)"
  rstate="$(envcfg remote_state)"
  stage_env_cfg="$(envcfg "${key}")"

  # terraform sub-command for the action (apply/destroy are auto-approve;
  # plan is a read-only dry-run).
  local -a tf
  case "${action}" in
    plan)    tf=(terraform plan -input=false -no-color) ;;
    apply)   tf=(terraform apply -auto-approve -input=false) ;;
    destroy) tf=(terraform destroy -auto-approve -input=false) ;;
    *)       err "unknown action: ${action} (want apply|plan|destroy)" ;;
  esac

  echo ""
  case "${action}" in
    apply)   echo "== ${display}: apply ==" ;;
    plan)    echo "== ${display}: plan (dry-run) ==" ;;
    destroy) echo "== ${display}: destroy ==" ;;
  esac

  # Per-stage credentials: reload the correct key file for THIS stage
  # (bootstrap uses the org-level owner key, stages 1-6 the lz key).
  # A key already exported in the shell wins, so this never clobbers the
  # caller's explicit credentials and is safe to re-run per stage in one
  # full apply/destroy loop.
  # The bootstrap branch needs the org-level key (day-0: bootstrap CREATES
  # the SA keys, so it can never be driven by one of its own products).
  # EXCEPTION: destroying bootstrap must keep the org-level key the driver
  # already loaded (destroy.sh) - reloading the infra-ops/lz key here would
  # trip the self-brick guard below. Apply/plan still reload normally.
  if [[ "${action}" == "destroy" && "${key}" == "bootstrap" ]]; then
    [[ -n "${SCW_ACCESS_KEY:-}" ]] || err "no SCW_ACCESS_KEY for bootstrap destroy (org-level key required)"
  else
    load_env_creds "${key}"
  fi

  # ---------------------------------------------------------------------
  # Self-brick guard (destroy only). The merged bootstrap stage owns BOTH the
  # SA keys that can drive it (the bootstrap SA key AND the lz deploy key) and
  # each SA's own org-wide IAM policies, all in a single state. `terraform
  # destroy` deletes the policy grants FIRST, so the driving key loses every
  # permission mid-run and the rest of the stage dies with 403 /
  # "insufficient permissions" (the api_key + DeleteBucket failures seen in
  # the dev teardown). This stage must be destroyed with an ORG-LEVEL key that
  # is not owned by any stage being destroyed (e.g. your own account key) -
  # exported keys already win over file-loaded ones, so simply exporting it in
  # the shell is enough. Fail fast with guidance instead of letting terraform
  # half-destroy the stage.
  # ---------------------------------------------------------------------
  if [[ "${action}" == "destroy" ]]; then
    local -a own_keys=()
    case "${key}" in
      bootstrap)
        # Resolve the keys owned by this stage from the per-env LOCAL
        # bootstrap state (single source of truth) - both the bootstrap SA
        # key and the lz deploy key - plus the .creds deploy-key file as a
        # fallback when the state is not parseable.
        local st="${REPO_ROOT}/scw-lz/envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate"
        while IFS= read -r ak; do
          [[ -n "${ak}" ]] && own_keys+=("${ak}")
        done < <(
          jq -r '.resources[]? | select(.type=="scaleway_iam_api_key" and ((.name=="bootstrap") or (.name=="lz_deploy"))) | .instances[0].attributes.access_key' "${st}" 2>/dev/null
        )
        ak="$(grep -Eo 'SCW_ACCESS_KEY=[^[:space:]]+' "${REPO_ROOT}/.creds/lz-${ENV_NAME}.env" 2>/dev/null | head -1 | cut -d= -f2- || true)"
        [[ -n "${ak}" ]] && own_keys+=("${ak}")
        ;;
    esac
    local own_key
    for own_key in "${own_keys[@]+"${own_keys[@]}"}"; do
      if [[ -n "${own_key}" && "${SCW_ACCESS_KEY:-}" == "${own_key}" ]]; then
        cat >&2 <<EOF

error: refusing to destroy stage '${display}' (${key}) with one of its own
       service-account keys (${own_key}).

       This stage's state holds BOTH the SA keys (bootstrap + lz deploy) AND
       both SAs' own IAM policies, so destroying it under either key revokes
       that key's permissions mid-run and the cleanup half-dies (403 /
       insufficient permissions). There is no ordering that fixes this: an SA
       key always dies with the stage that owns its grants.

       Run make destroy with an ORG-LEVEL key not owned by any stage being
       destroyed (your personal/owner key). Export it in the shell first -
       the loader never overrides exported credentials:

         set -a; source <your-org-key.env>; set +a
         make destroy ENV=${ENV_NAME}

       (or export SCW_ACCESS_KEY / SCW_SECRET_KEY directly, then re-run)
EOF
        exit 1
      fi
    done
  fi

  cd "${REPO_ROOT}/scw-lz/${dir}" || exit 1

  # Backend: bootstrap uses local state; every other stage uses the
  # shared remote backend configured per env. -reconfigure re-points the
  # backend without migrating state (the S3 bucket is hard-bound at init,
  # see CONVERSATION_MEMORY learning re env switching).
  if [[ "${key}" == "bootstrap" ]]; then
    terraform init -input=false
  else
    terraform init -input=false -reconfigure -backend-config="${back}"
  fi

  local identity_vars=(
    -var="organization_id=${ORG_ID}"
    -var="region=${REGION}"
    -var="zone=${ZONE}"
  )

  case "${key}" in
    bootstrap)
      # Per-env LOCAL state (one state file per env). Consumes the org-setup
      # tfvars (0-org-setup-<env>.tfvars) as optional variable overrides; the
      # org factory YAML (envs/<env>/data/org-<env>.yaml) carries the resource
      # definitions.
      # NOTE: the path is relative to THIS stage's cwd (scw-lz/bootstrap),
      # which is one level shallower than scw-lz/stages/<N> - so envcfg()
      # (stage-relative) cannot be used here.
      ocfg=()
      if [[ -f "${REPO_ROOT}/scw-lz/envs/${ENV_NAME}/0-org-setup-${ENV_NAME}-demo.tfvars" ]]; then
        ocfg+=("-var-file=../envs/${ENV_NAME}/0-org-setup-${ENV_NAME}-demo.tfvars")
      elif [[ -f "${REPO_ROOT}/scw-lz/envs/${ENV_NAME}/0-org-setup-${ENV_NAME}.tfvars" ]]; then
        ocfg+=("-var-file=../envs/${ENV_NAME}/0-org-setup-${ENV_NAME}.tfvars")
      fi
      iopn=()
      [[ -n "${INFRA_OPS_PROJECT_NAME:-}" ]] && iopn+=("-var=infra_ops_project_name=${INFRA_OPS_PROJECT_NAME}")
      "${tf[@]}" \
        "${identity_vars[@]}" \
        -var="project_id=${PROJECT_ID}" \
        -var="environment=${ENV_NAME}" \
        -var="enable_state_lock=true" \
        -var="state_retention_days=365" \
        -var="enable_state_sse=true" \
        -state="../envs/${ENV_NAME}/bootstrap-${ENV_NAME}.tfstate" \
        "${ocfg[@]+"${ocfg[@]}"}" \
        "${iopn[@]+"${iopn[@]}"}"
      ;;
    "1-security"|"2-networking"|"3-security-appliances"|"6-interconnection")
      # These stages do NOT declare `environment` (they derive it from
      # bootstrap's local state output); project_key is overridden on the CLI.
      cfg_args=()
      if [[ -f "${stage_env_cfg}" ]]; then
        cfg_args+=("-var-file=${stage_env_cfg}")
      elif [[ "${action}" == "apply" ]]; then
        err "missing required per-env tfvars for ${key}: ${stage_env_cfg}"
      else
        echo "  note: ${stage_env_cfg} not found - continuing without it (destroy needs only the CLI overrides)."
      fi
      "${tf[@]}" \
        "${cfg_args[@]+"${cfg_args[@]}"}" \
        -var-file="${prov}" \
        -var-file="${rstate}" \
        "${identity_vars[@]}" \
        -var="project_key=${ENV_NAME}" \
        "${extra_vars[@]+"${extra_vars[@]}"}"
      ;;
    "4-project-factory")
      # Uses parent_project_key from its own per-env tfvars (no project_key
      # override). The caller skips this stage entirely when the tfvars are
      # missing.
      pcfg=()
      [[ -f "${stage_env_cfg}" ]] && pcfg+=("-var-file=${stage_env_cfg}")
      "${tf[@]}" \
        "${pcfg[@]+"${pcfg[@]}"}" \
        -var-file="${prov}" \
        -var-file="${rstate}" \
        "${identity_vars[@]}" \
        "${extra_vars[@]+"${extra_vars[@]}"}"
      ;;
    "5-backup")
      # Backup stack: per-env tfvars are 5-backup-<env>.tfvars (same numbered
      # convention as every other stage), project comes from infra_ops_project_id
      # in those tfvars (declares `environment`, no project_key). Required for
      # destroy too -- the provider block reads infra_ops_project_id.
      bcfg="$(envcfg 5-backup)"
      [[ -f "${bcfg}" ]] || err "missing required per-env tfvars for ${key}: ${bcfg}"
      "${tf[@]}" \
        -var-file="${bcfg}" \
        -var-file="${prov}" \
        -var-file="${rstate}" \
        "${identity_vars[@]}" \
        -var="environment=${ENV_NAME}" \
        "${extra_vars[@]+"${extra_vars[@]}"}"
      ;;
    *)
      err "unknown stage: ${key}"
      ;;
  esac

  cd "${REPO_ROOT}" || exit 1
}
