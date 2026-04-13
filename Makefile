.DEFAULT_GOAL := help

SHELL := /bin/bash

# Tools installed by deps-* land in ~/.local/bin; export it so subsequent
# recipes (each a fresh subshell) can find them. Also needed inside act.
export PATH := $(HOME)/.local/bin:$(PATH)

# === Tool versions (pinned; Renovate-tracked via inline # renovate: comments) ===
# renovate: datasource=github-releases depName=koalaman/shellcheck
SHELLCHECK_VERSION := v0.11.0
# renovate: datasource=github-releases depName=rhysd/actionlint
ACTIONLINT_VERSION := v1.7.12
# renovate: datasource=github-releases depName=gitleaks/gitleaks
GITLEAKS_VERSION := v8.30.1
# renovate: datasource=github-releases depName=aquasecurity/trivy
TRIVY_VERSION := v0.69.3
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-36s\033[0m - %s\n", $$1, $$2}'

#deps: @ Verify required runtime tools are installed
deps:
	@for tool in docker kind kubectl helm curl jq base64; do \
		command -v $$tool >/dev/null 2>&1 || { echo "Error: $$tool required. See README Prerequisites."; exit 1; }; \
	done

#deps-shellcheck: @ Install shellcheck
deps-shellcheck:
	@command -v shellcheck >/dev/null 2>&1 || { echo "Installing shellcheck $(SHELLCHECK_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL -o /tmp/shellcheck.tar.xz https://github.com/koalaman/shellcheck/releases/download/$(SHELLCHECK_VERSION)/shellcheck-$(SHELLCHECK_VERSION).linux.x86_64.tar.xz && \
		tar -xJf /tmp/shellcheck.tar.xz -C /tmp && \
		install -m 755 /tmp/shellcheck-$(SHELLCHECK_VERSION)/shellcheck $$HOME/.local/bin/shellcheck && \
		rm -rf /tmp/shellcheck-$(SHELLCHECK_VERSION) /tmp/shellcheck.tar.xz; \
	}

#deps-actionlint: @ Install actionlint
deps-actionlint:
	@command -v actionlint >/dev/null 2>&1 || { echo "Installing actionlint $(ACTIONLINT_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL -o /tmp/actionlint.tar.gz https://github.com/rhysd/actionlint/releases/download/$(ACTIONLINT_VERSION)/actionlint_$(ACTIONLINT_VERSION:v%=%)_linux_amd64.tar.gz && \
		tar -xzf /tmp/actionlint.tar.gz -C $$HOME/.local/bin actionlint && \
		rm -f /tmp/actionlint.tar.gz; \
	}

#deps-gitleaks: @ Install gitleaks
deps-gitleaks:
	@command -v gitleaks >/dev/null 2>&1 || { echo "Installing gitleaks $(GITLEAKS_VERSION)..."; \
		mkdir -p $$HOME/.local/bin; \
		curl -sSfL -o /tmp/gitleaks.tar.gz https://github.com/gitleaks/gitleaks/releases/download/$(GITLEAKS_VERSION)/gitleaks_$(GITLEAKS_VERSION:v%=%)_linux_x64.tar.gz && \
		tar -xzf /tmp/gitleaks.tar.gz -C $$HOME/.local/bin gitleaks && \
		rm -f /tmp/gitleaks.tar.gz; \
	}

#deps-trivy: @ Install Trivy
deps-trivy:
	@command -v trivy >/dev/null 2>&1 || { echo "Installing trivy $(TRIVY_VERSION)..."; \
		curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b $$HOME/.local/bin $(TRIVY_VERSION); \
	}

#lint: @ Run shellcheck on all scripts + actionlint on all workflows
lint: deps-shellcheck deps-actionlint
	@shellcheck scripts/*.sh
	@actionlint .github/workflows/*.yml

#secrets: @ Scan for leaked secrets (gitleaks)
secrets: deps-gitleaks
	@gitleaks detect --source . --config .gitleaks.toml --verbose --redact --no-git

#trivy-fs: @ Scan filesystem for vulnerabilities, secrets, misconfigurations (fails on findings)
trivy-fs: deps-trivy
	@trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --exit-code 1 --ignorefile .trivyignore.yaml .

#trivy-config: @ Scan K8s manifests for security misconfigurations (fails on findings)
trivy-config: deps-trivy
	@trivy config --severity CRITICAL,HIGH --exit-code 1 --ignorefile .trivyignore.yaml k8s/

#mermaid-lint: @ Validate Mermaid diagrams in README.md
mermaid-lint:
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker required for mermaid-lint"; exit 1; }
	@set -euo pipefail; \
	MD_FILES=$$(grep -lF '```mermaid' README.md CLAUDE.md 2>/dev/null || true); \
	if [ -z "$$MD_FILES" ]; then echo "No Mermaid blocks found — skipping."; exit 0; fi; \
	FAILED=0; \
	for md in $$MD_FILES; do \
		echo "Validating Mermaid blocks in $$md..."; \
		LOG=$$(mktemp); \
		if docker run --rm -v "$$PWD:/data" \
			minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
			-i "/data/$$md" -o "/tmp/$$(basename $$md .md).svg" >"$$LOG" 2>&1; then \
			echo "  ✓ All blocks rendered cleanly."; \
		else \
			echo "  ✗ Parse error:"; sed 's/^/    /' "$$LOG"; FAILED=$$((FAILED + 1)); \
		fi; \
		rm -f "$$LOG"; \
	done; \
	if [ "$$FAILED" -gt 0 ]; then echo "Mermaid lint: $$FAILED file(s) failed."; exit 1; fi

#static-check: @ Composite quality gate (lint + secrets + trivy + mermaid-lint)
static-check: lint secrets trivy-fs trivy-config mermaid-lint
	@echo "Static check passed."

#ci: @ Full local CI pipeline (static-check + renovate-validate)
ci: static-check renovate-validate
	@echo "Local CI pipeline passed."

#install-all: @ Install all (kind k8s cluster, Nginx ingress, MetalLB, demo workloads)
install-all: deps
	@./scripts/kind-install-all.sh yes

#install-all-no-demo-workloads: @ Install all (kind k8s cluster, Nginx ingress, MetalLB)
install-all-no-demo-workloads: deps
	@./scripts/kind-install-all.sh no

#kind-up: @ docker-compose-style alias for install-all (bring the whole stack up)
kind-up: install-all

#kind-down: @ docker-compose-style alias for delete-cluster (tear the whole stack down)
kind-down: delete-cluster

#create-cluster: @ Create k8s cluster
create-cluster: deps
	@./scripts/kind-create.sh

#export-cert: @ Export k8s keys (client) and certificates (client, cluster CA)
export-cert: deps
	@./scripts/kind-export-cert.sh

#dashboard-install: @ Install Kubernetes Dashboard (Helm chart v7.x) and admin ServiceAccount
dashboard-install: deps
	@./scripts/kind-add-dashboard.sh

#dashboard-forward: @ Port-forward dashboard to https://localhost:8443 and open browser
dashboard-forward: deps
	@./scripts/kind-forward-dashboard.sh

#dashboard-token: @ Print the admin-user token for the Dashboard login screen
dashboard-token: deps
	@./scripts/kind-dashboard-token.sh

#k8s-dashboard: @ Alias for dashboard-install (backwards compatible)
k8s-dashboard: dashboard-install

#nginx-ingress: @ Install Nginx ingress
nginx-ingress: deps
	@./scripts/kind-add-ingress-nginx.sh

#metallb: @ Install MetalLB load balancer
metallb: deps
	@./scripts/kind-add-metallb.sh

#metrics-server: @ Install metrics-server for kubectl top / HPA
metrics-server: deps
	@./scripts/kind-add-metrics-server.sh

#kube-prometheus-stack: @ Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
kube-prometheus-stack: deps
	@./scripts/kind-add-kube-prometheus-stack.sh

#nfs-incluster: @ Install in-cluster NFS server + csi-driver-nfs (RWX, no host config)
nfs-incluster: deps
	@./scripts/kind-add-nfs-incluster.sh

#nfs-host-setup: @ Configure HOST as NFS server (Ubuntu/Debian, requires sudo)
nfs-host-setup:
	@./scripts/kind-add-nfs-host-setup.sh

#nfs-host-provisioner: @ Install csi-driver-nfs + StorageClass pointing at host NFS (pass NFS_SERVER=<ip>)
nfs-host-provisioner: deps
	@if [ -z "$(NFS_SERVER)" ]; then echo "Error: NFS_SERVER=<ip> required. Example: make nfs-host-provisioner NFS_SERVER=192.168.1.27"; exit 1; fi
	@./scripts/kind-add-nfs-host-provisioner.sh $(NFS_SERVER) $(if $(NFS_PATH),$(NFS_PATH),)

#deploy-app-nginx-ingress-localhost: @ Deploy httpd with ingress at http://demo.localdev.me:80/ (patches ingress-nginx-controller to LoadBalancer)
deploy-app-nginx-ingress-localhost: deps
	@./scripts/kind-deploy-app-nginx-ingress-localhost.sh

#deploy-app-helloweb: @ Deploy helloweb
deploy-app-helloweb: deps
	@./scripts/kind-deploy-app-helloweb.sh

#deploy-app-golang-hello-world-web: @ Deploy golang-hello-world-web app
deploy-app-golang-hello-world-web: deps
	@./scripts/kind-deploy-app-golang-hello-world-web.sh

#deploy-app-foo-bar-service: @ Deploy foo-bar-service app
deploy-app-foo-bar-service: deps
	@./scripts/kind-deploy-app-foo-bar-service.sh

#image-build: @ Build kubectl-test Docker image
image-build:
	@docker build -f ./images/Dockerfile -t kubectl-test .

#registry: @ Create a KinD cluster wired to a local Docker registry (localhost:5001)
registry: deps
	@./scripts/kind-with-registry.sh

#registry-test: @ Push hello-app:1.0 to the local registry and deploy it (run after 'make registry')
registry-test: deps
	@./scripts/test-registry.sh

#vm-up: @ Launch Ubuntu VM via Multipass with the full stack pre-provisioned (NAME=kind-host)
vm-up:
	@./scripts/vm-up.sh $(if $(NAME),$(NAME),) $(if $(CPUS),$(CPUS),) $(if $(MEMORY),$(MEMORY),) $(if $(DISK),$(DISK),)

#vm-down: @ Stop, delete and purge the VM (NAME=kind-host)
vm-down:
	@./scripts/vm-down.sh $(if $(NAME),$(NAME),)

#vm-ssh: @ Open an interactive shell inside the VM (NAME=kind-host)
vm-ssh:
	@./scripts/vm-ssh.sh $(if $(NAME),$(NAME),)

#vm-install-all: @ Run 'make install-all' inside the VM (NAME=kind-host)
vm-install-all:
	@./scripts/vm-install-all.sh $(if $(NAME),$(NAME),)

#renovate-validate: @ Validate renovate.json configuration
renovate-validate:
	@command -v npx >/dev/null 2>&1 || { echo "Error: npx required (install Node.js)."; exit 1; }
	@npx --yes --package renovate -- renovate-config-validator

#delete-cluster: @ Delete k8s cluster
delete-cluster: deps
	@./scripts/kind-delete.sh

.PHONY: help deps deps-shellcheck deps-actionlint deps-gitleaks deps-trivy \
	lint secrets trivy-fs trivy-config mermaid-lint static-check ci \
	install-all install-all-no-demo-workloads kind-up kind-down \
	create-cluster export-cert k8s-dashboard dashboard-install \
	dashboard-forward dashboard-token nginx-ingress metallb \
	metrics-server kube-prometheus-stack \
	nfs-incluster nfs-host-setup nfs-host-provisioner \
	deploy-app-nginx-ingress-localhost deploy-app-helloweb \
	deploy-app-golang-hello-world-web deploy-app-foo-bar-service \
	image-build registry registry-test renovate-validate delete-cluster \
	vm-up vm-down vm-ssh vm-install-all
