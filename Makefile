# Makefile for rhel-cc-pattern
# Run via: ./pattern.sh make <target>

.PHONY: install uninstall verify status help

install: ## Deploy the full rhel-cc-pattern end-to-end
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║          rhel-cc-pattern — Deployment Starting          ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Step 1/3: Bootstrapping AAP..."
	@bash scripts/aap-setup.sh
	@echo ""
	@echo "Step 2/3: Phase 1 — Attestation server..."
	@bash scripts/run-workflow.sh "rhel-cc-pattern: Phase 1 - Bootstrap Attestation Server"
	@echo ""
	@echo "Step 3/3: Full deployment..."
	@bash scripts/run-workflow.sh "rhel-cc-pattern: Deploy Full Pattern"
	@echo ""
	@$(MAKE) verify

uninstall: ## Destroy all Azure VMs
	@az group delete --name rhel-cc-pattern-rg --yes --no-wait
	@echo "Resource group deletion initiated"

verify: ## Run attestation tests and show results
	@bash scripts/verify.sh

status: ## Show current VM and service status
	@echo "=== Azure VMs ===" && \
	az vm list -g rhel-cc-pattern-rg --show-details \
	  --query "[].{name:name, ip:publicIps, state:powerState}" -o table 2>/dev/null || \
	echo "No VMs found"

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
