.DEFAULT_GOAL := help

SHELL := /bin/bash

# mise shims (shellcheck, actionlint, gitleaks, trivy, hadolint, act, jq, kind,
# kubectl — pinned in .mise.toml) must be on PATH for every recipe's fresh
# subshell. ~/.local/bin stays on PATH for the mise installer itself.
export PATH := $(HOME)/.local/share/mise/shims:$(HOME)/.local/bin:$(PATH)

# === Tool versions pinned in .mise.toml (Renovate-tracked via the mise manager).
# The constants below track tools NOT managed by mise: docker-image pins
# (MERMAID_CLI_VERSION, PLANTUML_VERSION, KIND_NODE_IMAGE) and a shared
# dual-use pin (KUBECTL_VERSION also feeds images/Dockerfile as a --build-arg,
# so it lives here AND in .mise.toml — keep them in sync).
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0
# renovate: datasource=docker depName=plantuml/plantuml
PLANTUML_VERSION := 1.2026.2
# renovate: datasource=docker depName=ghcr.io/andriykalashnykov/puml2drawio
PUML2DRAWIO_VERSION := 1.0.1
# renovate: datasource=github-tags depName=kubernetes/kubernetes
KUBECTL_VERSION := v1.36.0
# KIND_NODE_IMAGE is bumped together with kind in .mise.toml per KinD release notes.
KIND_NODE_IMAGE := kindest/node:v1.35.0
# renovate: datasource=docker depName=registry.k8s.io/cloud-provider-kind/cloud-controller-manager
CLOUD_PROVIDER_KIND_VERSION := v0.10.0
export CLOUD_PROVIDER_KIND_VERSION
# catthehacker/ubuntu tags use loose `act-YY.MM` format (Ubuntu LTS cadence);
# bumps require also updating runs-on in .github/workflows/*.yml.
# renovate: datasource=docker depName=catthehacker/ubuntu versioning=loose
ACT_UBUNTU_VERSION := act-24.04

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-36s\033[0m - %s\n", $$1, $$2}'

#deps-tools: @ Install pinned CLI tools via mise (auto-bootstraps mise). Used by quality gates (no docker/helm/curl/base64 required).
deps-tools:
	@# Local-only: bootstrap mise on first run. jdx/mise-action handles this in CI.
	@if [ -z "$$CI" ] && ! command -v mise >/dev/null 2>&1; then \
		echo "Installing mise (no root required, installs to ~/.local/bin)..."; \
		curl -fsSL https://mise.run | sh; \
		echo ""; \
		echo "mise installed. Activate it in your shell, then re-run 'make deps':"; \
		echo "  bash: echo 'eval \"\$$(~/.local/bin/mise activate bash)\"' >> ~/.bashrc"; \
		echo "  zsh:  echo 'eval \"\$$(~/.local/bin/mise activate zsh)\"'  >> ~/.zshrc"; \
		exit 0; \
	fi
	@# Install every tool pinned in .mise.toml. Runs in both local and CI
	@# (idempotent; no-op when already at the pinned version).
	@if command -v mise >/dev/null 2>&1; then \
		mise install; \
	else \
		echo "Error: mise required. Re-run 'make deps' after activating mise."; \
		exit 1; \
	fi

#deps-docker: @ Verify docker CLI is on PATH (used by image-build, mermaid-lint, diagrams, ci-run)
deps-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker required. See README Prerequisites."; exit 1; }

#deps: @ deps-tools + deps-docker + verify cluster-runtime deps (helm, curl, base64)
deps: deps-tools deps-docker
	@for tool in helm curl base64; do \
		command -v $$tool >/dev/null 2>&1 || { echo "Error: $$tool required. See README Prerequisites."; exit 1; }; \
	done

#deps-multipass: @ Verify Multipass is installed (required for vm-* targets)
deps-multipass:
	@command -v multipass >/dev/null 2>&1 || { echo "Error: multipass required. Install from https://multipass.run/install"; exit 1; }

#deps-renovate: @ Verify npx is available (required for renovate-validate)
deps-renovate:
	@command -v npx >/dev/null 2>&1 || { echo "Error: npx required (install Node.js)."; exit 1; }

#lint: @ Run shellcheck + executable-mode check on scripts, actionlint on workflows, hadolint on Dockerfile
lint: deps-tools
	@# Catch shell scripts committed without +x — they exit 126 "Permission
	@# denied" in CI. `make ci-run` only exercises static-check + docker jobs
	@# (not e2e), so scripts called from e2e-only paths slip through locally.
	@NONEXEC=$$(find scripts -name '*.sh' -not -executable -print); \
	if [ -n "$$NONEXEC" ]; then \
		echo "Error: shell scripts missing +x (run 'chmod +x <file>'):"; \
		echo "$$NONEXEC" | sed 's/^/  /'; \
		exit 1; \
	fi
	@shellcheck scripts/*.sh
	@actionlint .github/workflows/*.yml
	@hadolint images/Dockerfile

#secrets: @ Scan for leaked secrets (gitleaks)
secrets: deps-tools
	@gitleaks detect --source . --config .gitleaks.toml --verbose --redact --no-git

#trivy-fs: @ Scan filesystem for vulnerabilities, secrets, misconfigurations (fails on findings)
trivy-fs: deps-tools
	@trivy fs --scanners vuln,secret,misconfig --severity CRITICAL,HIGH --exit-code 1 --ignorefile .trivyignore.yaml .

#trivy-config: @ Scan K8s manifests for security misconfigurations (fails on findings)
trivy-config: deps-tools
	@trivy config --severity CRITICAL,HIGH --exit-code 1 --ignorefile .trivyignore.yaml k8s/

#mermaid-lint: @ Validate Mermaid diagrams in all *.md files
mermaid-lint: deps-tools deps-docker
	@set -euo pipefail; \
	MD_FILES=$$(git ls-files '*.md' 2>/dev/null | xargs -r grep -lF '```mermaid' 2>/dev/null || true); \
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

DIAGRAM_DIR := docs/diagrams
DIAGRAM_SRC := $(wildcard $(DIAGRAM_DIR)/*.puml)
DIAGRAM_OUT := $(patsubst $(DIAGRAM_DIR)/%.puml,$(DIAGRAM_DIR)/out/%.png,$(DIAGRAM_SRC))

#diagrams: @ Render PlantUML architecture diagrams to PNG via pinned plantuml/plantuml docker image
diagrams: deps-docker $(DIAGRAM_OUT)

$(DIAGRAM_DIR)/out/%.png: $(DIAGRAM_DIR)/%.puml
	@mkdir -p $(DIAGRAM_DIR)/out
	@docker run --rm --user $$(id -u):$$(id -g) \
		-e HOME=/tmp -e _JAVA_OPTIONS=-Duser.home=/tmp \
		-v "$(CURDIR)/$(DIAGRAM_DIR):/work" -w /work \
		plantuml/plantuml:$(PLANTUML_VERSION) -tpng -o out $(notdir $<)

#diagrams-check: @ Verify committed diagram PNGs match current .puml source
diagrams-check: diagrams
	@git diff --exit-code -- $(DIAGRAM_DIR)/out >/dev/null 2>&1 || \
		{ echo "ERROR: Diagram source changed but rendered PNG was not committed. Run 'make diagrams' and commit."; exit 1; }
	@echo "Diagrams in sync."

#diagrams-clean: @ Remove rendered diagram PNGs + .drawio exports
diagrams-clean:
	@rm -rf $(DIAGRAM_DIR)/out $(DIAGRAM_DIR)/drawio

#diagrams-drawio: @ Convert PlantUML .puml sources to editable draw.io .drawio XML (pinned ghcr.io/andriykalashnykov/puml2drawio)
diagrams-drawio: deps-docker
	@mkdir -p $(DIAGRAM_DIR)/drawio
	@docker run --rm --user $$(id -u):$$(id -g) \
		-v "$(CURDIR)/$(DIAGRAM_DIR):/work" -w /work \
		ghcr.io/andriykalashnykov/puml2drawio:$(PUML2DRAWIO_VERSION) \
		. -o drawio/
	@echo "Wrote $(DIAGRAM_DIR)/drawio/*.drawio"

#static-check: @ Composite quality gate (lint + secrets + trivy + mermaid-lint + diagrams-check)
static-check: lint secrets trivy-fs trivy-config mermaid-lint diagrams-check
	@echo "Static check passed."

#ci: @ Full local CI pipeline (static-check + renovate-validate)
ci: static-check renovate-validate
	@echo "Local CI pipeline passed."

#ci-run: @ Run GitHub Actions workflow locally via act (static-check + docker; e2e skipped — KinD Docker-in-Docker flakes under act)
ci-run: deps-tools deps-docker
	@docker container prune -f 2>/dev/null || true
	@# Random artifact port + dir so concurrent ci-run invocations from other
	@# projects don't collide on act's host-global defaults (34567, /tmp/act-artifacts).
	@ACT_PORT=$$(shuf -i 40000-59999 -n 1); \
	ARTIFACT_PATH=$$(mktemp -d -t act-artifacts.XXXXXX); \
	for j in static-check docker; do \
		echo "==== act push --job $$j ===="; \
		act push --job $$j \
			--container-architecture linux/amd64 \
			-P ubuntu-24.04=catthehacker/ubuntu:$(ACT_UBUNTU_VERSION) \
			--artifact-server-port "$$ACT_PORT" \
			--artifact-server-path "$$ARTIFACT_PATH" || exit 1; \
	done

#install-all: @ Install all (kind cluster, Nginx ingress, cloud-provider-kind LoadBalancer, demo workloads; override with LB=metallb)
install-all: deps
	@./scripts/kind-install-all.sh yes

#install-all-no-demo-workloads: @ Install all (kind cluster, Nginx ingress, cloud-provider-kind LoadBalancer; override with LB=metallb)
install-all-no-demo-workloads: deps
	@./scripts/kind-install-all.sh no

#kind-up: @ docker-compose-style alias for install-all (bring the whole stack up)
kind-up: install-all

#kind-down: @ docker-compose-style alias for delete-cluster (tear the whole stack down)
kind-down: delete-cluster

#lb-cpk: @ Install cloud-provider-kind (primary LoadBalancer — alternative: 'make lb-metallb')
lb-cpk: deps-docker
	@./scripts/kind-add-cloud-provider-kind.sh

#create-cluster: @ Create k8s cluster (pinned to KIND_NODE_IMAGE)
create-cluster: deps
	@KIND_NODE_IMAGE=$(KIND_NODE_IMAGE) ./scripts/kind-create.sh

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

#lb-metallb: @ Install MetalLB load balancer (alternative to 'make lb-cpk'; use LB=metallb with install-all)
lb-metallb: deps
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
image-build: deps-docker
	@docker build --build-arg KUBECTL_VERSION=$(KUBECTL_VERSION) -f ./images/Dockerfile -t kubectl-test .

#image-test: @ Verify kubectl-test image runs and kubectl is available inside it
image-test: image-build
	@docker run --rm kubectl-test kubectl version --client >/dev/null
	@echo "kubectl-test image runtime check passed."

#registry: @ Create a KinD cluster wired to a local Docker registry (localhost:5001)
registry: deps
	@./scripts/kind-with-registry.sh

#registry-test: @ Push hello-app:1.0 to the local registry and deploy it (run after 'make registry')
registry-test: deps
	@./scripts/test-registry.sh

#vm-up: @ Launch Ubuntu VM via Multipass with the full stack pre-provisioned (NAME=kind-host)
vm-up: deps-multipass
	@./scripts/vm-up.sh $(if $(NAME),$(NAME),) $(if $(CPUS),$(CPUS),) $(if $(MEMORY),$(MEMORY),) $(if $(DISK),$(DISK),)

#vm-down: @ Stop, delete and purge the VM (NAME=kind-host)
vm-down: deps-multipass
	@./scripts/vm-down.sh $(if $(NAME),$(NAME),)

#vm-ssh: @ Open an interactive shell inside the VM (NAME=kind-host)
vm-ssh: deps-multipass
	@./scripts/vm-ssh.sh $(if $(NAME),$(NAME),)

#vm-install-all: @ Run 'make install-all' inside the VM (NAME=kind-host)
vm-install-all: deps-multipass
	@./scripts/vm-install-all.sh $(if $(NAME),$(NAME),)

#renovate-validate: @ Validate renovate.json configuration
renovate-validate: deps-renovate
	@npx --yes --package renovate -- renovate-config-validator

#delete-cluster: @ Delete k8s cluster
delete-cluster: deps
	@./scripts/kind-delete.sh

#e2e: @ Smoke-test deployed services on a running cluster
e2e: deps
	@./scripts/e2e-smoke.sh

#clean: @ Tear down cluster and remove scratch artifacts
clean:
	@./scripts/kind-delete.sh 2>/dev/null || true
	@rm -rf /tmp/act-artifacts

.PHONY: help deps deps-tools deps-docker deps-multipass deps-renovate \
	lint secrets trivy-fs trivy-config mermaid-lint static-check ci ci-run \
	install-all install-all-no-demo-workloads kind-up kind-down \
	lb-cpk lb-metallb create-cluster export-cert k8s-dashboard dashboard-install \
	dashboard-forward dashboard-token nginx-ingress \
	metrics-server kube-prometheus-stack \
	nfs-incluster nfs-host-setup nfs-host-provisioner \
	deploy-app-nginx-ingress-localhost deploy-app-helloweb \
	deploy-app-golang-hello-world-web deploy-app-foo-bar-service \
	image-build image-test registry registry-test renovate-validate delete-cluster \
	e2e clean diagrams diagrams-check diagrams-clean diagrams-drawio \
	vm-up vm-down vm-ssh vm-install-all
