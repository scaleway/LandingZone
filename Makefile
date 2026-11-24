# ---------------------------------------------------------------------------
# Scaleway Landing Zone Toolkit -- Makefile
#
# Typical flow, in order:
#
#   make init                        install providers/modules (offline-safe)
#   make fmt                         format every terraform source file
#   make validate                    full quality gate (fmt-check, validate, hygiene)
#   make plan    [STAGE=n]           dry-run: what would change, change nothing
#   make apply   [STAGE=n]           deploy (bootstrap first, then stages 1-6)
#   make destroy [STAGE=n]           tear down (see destroy variants below)
#
# One command, stage as a flag:
#   make apply    STAGE=3            deploy only stage 3
#   make destroy  STAGE=3            tear down only stage 3
#   make destroy  STAGE=bootstrap    tear down the bootstrap foundation (last)
#
# STAGE accepts the key ("3-security-appliances"), the number ("3"), or the
# alias ("stage-3"). Unset = all stages. The former per-stage targets
# (stage-1..6, destroy-stage-N) are gone - use the STAGE= flag instead.
#
# Teardown order: destroy the workload stages first (make destroy, optionally
# destroy-keep-bootstrap for stage-1 too), then the foundation last
# (make destroy STAGE=bootstrap - it loads the org-level owner key
# automatically).
#
# Environment:
#   ENV=dev|prod             (default: dev)
#   ORG_ID                   required (export it; bootstrap also writes it)
#   SCW_ACCESS_KEY/SCW_SECRET_KEY  required for cloud targets; bootstrap
#                            generates one key per project and stages load it
#                            automatically (see bootstrap README)
#   REGION=fr-par  ZONE=fr-par-2   (defaults)
#
# Extra targets:
#   make bootstrap                   day-0 seed, run once per env before stages
#   make apply-existing              apply skipping bootstrap (already done)
#   make destroy-keep-bootstrap      teardown workload stages + stage-1, keep foundation
#   make delete-s3 BUCKET=<name>     empty + delete a leftover bucket
#   make fw-test                     run the firewall test battery
#   make test                        offline regression suite
#   make help                        this summary
# ---------------------------------------------------------------------------

.PHONY: help init fmt validate plan apply bootstrap apply-existing destroy \
        destroy-keep-bootstrap delete-s3 fw-test-env fw-test \
        delete-vpn-secrets clean test

# ---------------------------------------------------------------------------
# Repo hygiene (no cloud) - run before anything else
# ---------------------------------------------------------------------------

# Install providers/modules in every terraform dir. FORCE=1 re-inits -upgrade.
init:
	@terraform version >/dev/null 2>&1 || { echo "error: terraform not on PATH"; exit 1; }
	@missing=0; \
	for d in scw-lz/bootstrap scw-lz/stages/*/ samples/*/; do \
		[ -d "$${d}" ] || continue; \
		[ -n "$$(ls "$${d}"/*.tf 2>/dev/null | head -1)" ] || { echo "init: skipping $${d} (no .tf files)"; continue; }; \
		if [ -d "$${d}/.terraform" ] && [ -z "$${FORCE:-}" ]; then \
			echo "init: skipping $${d} (already initialized - FORCE=1 to re-init)"; \
		else \
			extra=""; [ -n "$${FORCE:-}" ] && extra=" -upgrade"; \
			echo "init: $${d}"; \
			(cd "$${d}" && terraform init -input=false -backend=false$${extra}) || { echo "init FAILED: $${d}"; missing=1; }; \
		fi; \
	done; \
	[ "$${missing}" -eq 0 ] || exit 1

# Format every terraform source file (modules + bootstrap + stages + samples).
fmt:
	terraform fmt -recursive modules/ scw-lz/bootstrap scw-lz/stages samples/

# Quality gate: fmt-check + validate + lint + hygiene + offline tests.
validate:
	./scripts/validate.sh

# ---------------------------------------------------------------------------
# Cloud lifecycle - plan, then apply, then destroy
# ---------------------------------------------------------------------------

# Dry-run only: show what terraform would change, change nothing.
plan:
	./scripts/apply.sh $(ENV) --plan $(if $(STAGE),--stage $(STAGE),)

# Deploy: bootstrap first, then all stages in order (or one stage only).
apply:
	./scripts/apply.sh $(ENV) $(if $(STAGE),--stage $(STAGE),)

# Day-0 seed: org setup (projects, IAM, SSH, KMS, audit, secrets) + the state
# bucket + both per-project credential files. Run once per env, before stages.
bootstrap:
	./scripts/apply.sh $(ENV) --stage bootstrap

# Apply with bootstrap skipped (already bootstrapped).
apply-existing:
	./scripts/apply.sh $(ENV) --skip-bootstrap

# Tear down the workload stages (2-6, reverse order). STAGE=<n> destroys only
# that one stage; STAGE=bootstrap destroys the foundation. Without STAGE the
# stage-1 security baseline + bootstrap are kept. Destroy the workloads first,
# then the foundation last (STAGE=bootstrap auto-loads the org owner key).
destroy:
	./scripts/destroy.sh $(ENV) $(if $(STAGE),--stage $(STAGE),)

# Teardown workload stages (2-6) + stage-1, keep the bootstrap foundation.
destroy-keep-bootstrap:
	./scripts/destroy.sh $(ENV) --everything --skip-bootstrap

# ---------------------------------------------------------------------------
# Operational helpers
# ---------------------------------------------------------------------------

# Empty (objects + versions) then delete a leftover S3 bucket.
#   make delete-s3 BUCKET=lz-dev-image-import -y
#   make delete-s3 BUCKET=lz-dev-terraform-state ARGS="--creds lz-dev-infra-ops -y"
delete-s3:
	./scripts/delete_s3.sh "$(BUCKET)" $(ENV) $(ARGS)

# Regenerate scw-lz/envs/<env>/test-firewalls.env from live stage-3 state
# (run after a rebuild so IPs/VIPs are fresh).
fw-test-env:
	./scripts/gen_fw_battery_env.sh $(ENV)

# Run the firewall test battery (providers/opnsense/test-firewalls.sh).
#   make fw-test ENV=prod               # prod battery
#   make fw-test ENV=prod ARGS="--ensure"
fw-test:
	ENV="$(ENV)" ./scw-lz/stages/3-security-appliances/providers/opnsense/test-firewalls.sh $(ARGS)

# Purge leftover managed-S2S-VPN PSK secrets that survive a destroy.
delete-vpn-secrets:
	./scripts/delete_vpn_secrets.sh $(ENV) $(ARGS)

# Offline regression suite (no cloud, no network).
test:
	./tests/run-tests.sh

# Remove local .terraform dirs (re-run `make init` after).
clean:
	rm -rf scw-lz/*/.terraform scw-lz/stages/*/.terraform samples/*/.terraform
	rm -f scw-lz/.terraform.lock.hcl scw-lz/stages/*/.terraform.lock.hcl samples/*/.terraform.lock.hcl

help:
	@echo "Scaleway Landing Zone Toolkit"
	@echo ""
	@echo "FLOW (in order):"
	@echo "  make init                    install providers/modules (offline-safe)"
	@echo "  make fmt                     format all terraform source"
	@echo "  make validate                quality gate (fmt-check, validate, hygiene)"
	@echo "  make plan                    dry-run: show what would change"
	@echo "  make apply                   deploy all stages in order"
	@echo "  make destroy                 tear down workload stages (2-6)"
	@echo "  make bootstrap               day-0 seed - run first, once per env"
	@echo ""
	@echo "TEARDOWN ORDER (workloads first, foundation last):"
	@echo "  make destroy                   workload stages (2-6), keep stage-1 + bootstrap"
	@echo "  make destroy-keep-bootstrap    + stage-1, keep bootstrap foundation"
	@echo "  make destroy STAGE=bootstrap   foundation only (loads .creds/lz-creds.env)"
	@echo ""
	@echo "STAGE AS A FLAG:"
	@echo "  make apply    STAGE=3          deploy only stage 3"
	@echo "  make apply    STAGE=3 ENV=prod  ... against the prod env"
	@echo "  make plan     STAGE=3          dry-run stage 3 (no changes)"
	@echo "  make destroy  STAGE=3          tear down only stage 3"
	@echo "  STAGE accepts: key (3-security-appliances) | number (3) | alias (stage-3)"
	@echo ""
	@echo "ENV (default dev), ORG_ID + SCW key required for cloud targets."
	@echo "Bootstrap writes one key per project; stages load it automatically."
	@echo ""
	@echo "MORE:  make apply-existing | make fw-test | make delete-s3 BUCKET=<name> | make test | make clean"
	@echo "       make help"
