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

- **ci.yml** — runs on push to `main`, tags `v*`, and PRs. Four jobs: `static-check` → (`docker` ‖ `e2e`) → `ci-pass`. The `e2e` job uses `make deps` + `make create-cluster` (kind / kubectl / kindest/node versions pinned in `Makefile`, Renovate-tracked), runs all install/deploy scripts, then runs `make e2e` (delegates to `scripts/e2e-smoke.sh`) for body-asserting smoke tests via `docker exec` curl. `helm/kind-action` was dropped in favor of explicit `make` invocations to avoid the action's built-in Post-step teardown flaking on Docker daemon `did not receive an exit event` errors at job-end.
- **cleanup-runs.yml** — weekly cron (Sunday midnight). Two jobs: `cleanup-runs` (prunes old runs, keeps latest 5) and `cleanup-caches` (deletes caches from closed PR branches).

## Dependencies

Runtime (user provides): Docker, kind, kubectl, helm, curl, jq, base64.

Quality-gate tools (auto-installed on first `make lint` / `make static-check` into `$HOME/.local/bin`, pinned via `# renovate:` comments in the Makefile): shellcheck, actionlint, hadolint, gitleaks, trivy, act. Plus `minlag/mermaid-cli` via docker.

No Go modules; no package manager lockfiles.

## Upgrade Backlog

Deferred items from `/upgrade-analysis` (2026-04-14). Resolve when actionable; Renovate should handle most via the `dockerfile` and `custom.regex` managers.

- [ ] **HIGH**: `images/Dockerfile` base image `alpine:3.16.2` is EOL (Alpine 3.16 EOL May 2024). Bump to a supported tag (e.g., `alpine:3.21`). Renovate `dockerfile` manager should propose this automatically — check open PRs.
- [ ] **LOW**: `images/Dockerfile` installs kubectl via `curl … stable.txt` at build time — not reproducible. Pin to `KUBECTL_VERSION` (share the Makefile constant via build-arg) if the image becomes load-bearing.
- [ ] **LOW**: `KUBECTL_VERSION` Renovate datasource is `github-tags`. Works for kubernetes/kubernetes but `github-releases` is the skill-canonical datasource — consider switching if PR noise increases.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
