# CLAUDE.md

## Project Overview

**kind-cluster** is a Shell/Kubernetes project for creating and managing local Kubernetes clusters using Docker with [KinD](https://kind.sigs.k8s.io/). It provides scripts for installing cluster components (Nginx ingress, MetalLB, dashboard) and deploying demo workloads.

- **Owner**: AndriyKalashnykov/kind-cluster
- **License**: MIT
- **Language**: Shell (Bash scripts)

## Repository Structure

```
Makefile              # Task runner with help target
scripts/              # Bash scripts for cluster lifecycle and app deployment
k8s/                  # Kubernetes manifests (kind config, dashboard, NFS, etc.)
images/               # Dockerfiles (kubectl-test image)
.github/workflows/    # CI: end2end-tests.yml, cleanup-runs.yml
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

# Local quality gates (all auto-install pinned tools into ~/.local/bin on first run)
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

- **ci.yml** — runs on push to `main`, tags `v*`, and PRs. Three jobs: `static-check` → `e2e` → `ci-pass`. The `e2e` job pins kind v0.31.0 / kubectl v1.35.1 / kindest/node v1.35.0 (tracked by Renovate), uses `helm/kind-action` to spin up a KinD cluster, runs all install/deploy scripts, then runs `make e2e` (delegates to `scripts/e2e-smoke.sh`) for body-asserting smoke tests via `docker exec` curl.
- **cleanup-runs.yml** — weekly cron (Sunday midnight). Two jobs: `cleanup-runs` (prunes old runs, keeps latest 5) and `cleanup-caches` (deletes caches from closed PR branches).

## Dependencies

Runtime (user provides): Docker, kind, kubectl, helm, curl, jq, base64.

Quality-gate tools (auto-installed on first `make lint` / `make static-check` into `$HOME/.local/bin`, pinned via `# renovate:` comments in the Makefile): shellcheck, actionlint, hadolint, gitleaks, trivy, act. Plus `minlag/mermaid-cli` via docker.

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
