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
```

## CI/CD

- **end2end-tests.yml** -- runs on push to `main`, tags `v*`, and PRs. Uses `helm/kind-action` to spin up a KinD cluster, then runs all install and deploy scripts.
- **cleanup-runs.yml** -- weekly cron (Sunday midnight) to prune old workflow runs.

## Dependencies

- Docker, kind, kubectl, helm, curl, jq, base64
- No Go modules; no package manager lockfiles

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
