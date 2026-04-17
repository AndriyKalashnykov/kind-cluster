# CLAUDE.md

## Project Overview

**kind-cluster** is a Shell/Kubernetes project for creating and managing local Kubernetes clusters using Docker with [KinD](https://kind.sigs.k8s.io/). It provides scripts for installing cluster components (Nginx ingress, MetalLB, dashboard) and deploying demo workloads.

- **Owner**: AndriyKalashnykov/kind-cluster
- **License**: MIT
- **Language**: Shell (Bash scripts)

## Repository Structure

```
Makefile              # Task runner with help target
.mise.toml            # Pinned tool versions (shellcheck, actionlint, gitleaks,
                      #   trivy, hadolint, act, jq, kind, kubectl)
scripts/              # Bash scripts for cluster lifecycle and app deployment
k8s/                  # Kubernetes manifests (kind config, dashboard, NFS, etc.)
images/               # Dockerfiles (kubectl-test image)
.github/workflows/    # CI: ci.yml, cleanup-runs.yml
```

## Common Commands

```bash
make help                              # List all available targets
make create-cluster                    # Create KinD cluster
make install-all                       # Full install: cluster + ingress + MetalLB + demo apps
make install-all-no-demo-workloads     # Cluster + ingress + MetalLB (no demo apps)
make delete-cluster                    # Tear down cluster

# Multipass VM (host-agnostic alternative)
make vm-up [NAME=…]                    # Launch Ubuntu 22.04 VM (cloud-init provisions Docker + kind + kubectl + helm)
make vm-install-all                    # Run `make install-all` inside the VM
make vm-ssh                            # Open shell inside the VM
make vm-down                           # Stop + delete + purge the VM

# Local quality gates (pinned tools installed on first run via `make deps`;
# mise is auto-bootstrapped into ~/.local/bin if missing)
make lint                              # shellcheck + actionlint + hadolint
make secrets                           # gitleaks (suppressions: .gitleaks.toml)
make trivy-fs                          # Trivy CVE/secret/misconfig scan (suppressions: .trivyignore.yaml)
make trivy-config                      # Trivy K8s manifest scan
make mermaid-lint                      # Validate mermaid diagrams in all *.md files (via docker)
make static-check                      # Composite: all of the above
make ci                                # static-check + renovate-validate
make ci-run                            # Run GitHub Actions workflow locally via act
```

## CI/CD

- **ci.yml** — runs on push to `main`, tags `v*`, and PRs. Four jobs: `static-check` → (`docker` ‖ `e2e`) → `ci-pass`. Both `static-check` and `e2e` use `jdx/mise-action` to install the pinned toolchain from `.mise.toml` (kind, kubectl, jq, shellcheck, actionlint, gitleaks, trivy, hadolint, act — Renovate-tracked via the mise manager). The `e2e` job then runs `make deps` (verifies docker/helm/curl/base64 + idempotent `mise install`) + `make create-cluster`, runs all install/deploy scripts, then `make e2e` (delegates to `scripts/e2e-smoke.sh`) for body-asserting smoke tests via `docker exec` curl. `helm/kind-action` was dropped in favor of explicit `make` invocations to avoid the action's built-in Post-step teardown flaking on Docker daemon `did not receive an exit event` errors at job-end.
- **cleanup-runs.yml** — weekly cron (Sunday midnight). Two jobs: `cleanup-runs` (prunes old runs, keeps latest 5) and `cleanup-caches` (deletes caches from closed PR branches).

## Dependencies

Runtime (user provides): Docker, helm, curl, base64.

Pinned in [`.mise.toml`](./.mise.toml) and installed by `make deps` via [mise](https://mise.jdx.dev): `kind`, `kubectl`, `jq`, `shellcheck`, `actionlint`, `gitleaks`, `trivy`, `hadolint`, `act`. `make deps` auto-bootstraps mise into `~/.local/bin` if missing, then runs `mise install` (idempotent; no-op at pinned versions).

Docker-image-pinned in Makefile (Renovate-tracked via inline `# renovate:` comments): `KUBECTL_VERSION` (shared with `images/Dockerfile` `--build-arg`), `MERMAID_CLI_VERSION`, `PLANTUML_VERSION`, `KIND_NODE_IMAGE`.

No Go modules; no package manager lockfiles.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
