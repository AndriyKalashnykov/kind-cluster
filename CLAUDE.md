# CLAUDE.md

## Project Overview

**kind-cluster** is a Shell/Kubernetes project for creating and managing local Kubernetes clusters using Docker with [KinD](https://kind.sigs.k8s.io/). It provides scripts for installing cluster components (Traefik ingress, LoadBalancer provider — cloud-provider-kind by default with MetalLB as alternative, Headlamp UI) and deploying demo workloads.

- **Owner**: AndriyKalashnykov/kind-cluster
- **License**: MIT
- **Language**: Shell (Bash scripts)

## Repository Structure

```
Makefile              # Task runner with help target
.mise.toml            # Pinned tool versions (shellcheck, actionlint, gitleaks,
                      #   trivy, hadolint, act, bats, jq, kind, kubectl)
scripts/              # Bash scripts for cluster lifecycle and app deployment
                      #   (lib.sh = sourceable helpers; kind-add-* installers;
                      #    migrate-from-metallb.sh; e2e-*.sh smoke tests)
tests/                # bats unit tests for scripts/lib.sh (make test)
k8s/                  # Kubernetes manifests (kind config, Headlamp, NFS, gateway/, etc.)
images/               # Dockerfiles (kubectl-test image)
docs/diagrams/        # PlantUML C4 sources (.puml) + rendered PNGs (out/)
                      #   (drawio/ holds on-demand `make diagrams-drawio` exports; gitignored)
docs/                 # gateway-api-ingress.md (Gateway API / ingress comparison)
vm/                   # Multipass cloud-init playbook
.github/workflows/    # CI: ci.yml, e2e-metallb.yml, monitoring-test.yml,
                      #   registry-test.yml, gateway-test.yml, cleanup-runs.yml
```

## Common Commands

```bash
make help                              # List all available targets
make kind-up                           # Alias for install-all (bring the whole stack up)
make kind-create                       # Create KinD cluster only
make install-all                       # Full install: cluster + ingress + cloud-provider-kind + demo apps
make install-all-no-demo-workloads     # Cluster + ingress + cloud-provider-kind (no demo apps)
LB=metallb make install-all            # Same as install-all but with MetalLB instead of cloud-provider-kind
make kind-down                         # Alias for kind-destroy (tear the whole stack down)
make kind-destroy                      # Delete cluster + clean up cloud-provider-kind sidecars

# LoadBalancer add-ons
make lb-cpk                            # Install cloud-provider-kind (primary; already part of install-all)
make lb-metallb                        # Install MetalLB (alternative to lb-cpk)

# Multipass VM (host-agnostic alternative)
make vm-up [NAME=…]                    # Launch Ubuntu 22.04 VM (cloud-init provisions Docker + kind + kubectl + helm)
make vm-install-all                    # Run `make install-all` inside the VM
make vm-ssh                            # Open shell inside the VM
make vm-down                           # Stop + delete + purge the VM

# Local quality gates (pinned tools installed on first run via `make deps`;
# mise is auto-bootstrapped into ~/.local/bin if missing)
make lint                              # shellcheck + actionlint + hadolint
make test                              # bats unit tests for scripts/lib.sh helpers
make secrets                           # gitleaks (suppressions: .gitleaks.toml)
make trivy-fs                          # Trivy CVE/secret/misconfig scan (suppressions: .trivyignore.yaml)
make trivy-config                      # Trivy K8s manifest scan
make mermaid-lint                      # Validate mermaid diagrams in all *.md files (via docker)
make diagrams                          # Render PlantUML C4 diagrams to PNG (via docker)
make diagrams-check                    # Verify committed PNGs match docs/diagrams/*.puml (via docker)
make static-check                      # Composite: all of the above
make ci                                # static-check + renovate-validate
make ci-run                            # Run GitHub Actions workflow locally via act (skips e2e — see below)
make e2e                               # install-all + e2e-smoke (full pipeline; fresh-checkout convenience)
make e2e-smoke                         # Body-asserting smoke test on a running cluster (no install)
make vulncheck                         # Alias for trivy-fs (portfolio-standard target name)

# Local registry cluster (separate from install-all)
make registry                          # Create a KinD cluster wired to a local registry (localhost:5001)
make registry-test                     # Push hello-app:2.0 to the local registry and deploy it (run after 'make registry')

# Gateway API (opt-in, alongside classic Ingress — see docs/gateway-api-ingress.md)
make gateway-traefik                   # Enable Traefik's Gateway API provider + demo HTTPRoutes (*.gw.localdev.me)
make gateway-istio                     # Install Istio as a 2nd Gateway API controller (own LB IP, same apps)
make gateway-nginx                     # Install NGINX Gateway Fabric as another Gateway API controller (own LB IP, same apps)
make gateway-contour                   # Install Project Contour (Gateway provisioner) as another Gateway API controller (own LB IP, same apps)
TEST_GATEWAY_API=yes make e2e-smoke    # Smoke-assert all Gateway API controllers (after the targets above)
```

`make ci-run` only iterates `static-check` + `docker` jobs under `act`. The `e2e` and `e2e-metallb` jobs are skipped because KinD's Docker-in-Docker requirement is unstable under `act push`. Push to a feature branch and watch the real workflow when changing anything in the e2e path (deploy scripts, ingress wiring, K8s manifests).

## CI/CD

- **ci.yml** — runs on push to `main`, tags `v*`, and PRs. Five jobs: `changes` → `static-check` → (`docker` ‖ `e2e`) → `ci-pass`. The `changes` job uses `dorny/paths-filter` to detect whether any non-doc file changed; downstream jobs short-circuit on doc-only changes via `if: needs.changes.outputs.code == 'true'`. `static-check` and `e2e` use `jdx/mise-action` to install the pinned toolchain from `.mise.toml` (kind, kubectl, jq, shellcheck, actionlint, gitleaks, trivy, hadolint, act — Renovate-tracked via the mise manager). The `e2e` job installs **cloud-provider-kind** as the LoadBalancer provider, runs all install/deploy scripts, polls until the ingress route is data-plane-ready (K1.5 — IP assigned ≠ IP routable), then `make e2e-smoke` (delegates to `scripts/e2e-smoke.sh`) for body-asserting smoke tests via `docker exec` curl. `helm/kind-action` was dropped in favor of explicit `make` invocations to avoid the action's built-in Post-step teardown flaking on Docker daemon `did not receive an exit event` errors at job-end.
- **e2e-metallb.yml** — weekly cron (Sunday 04:00 UTC) + `workflow_dispatch` + push on its MetalLB/migration scripts and the shared smoke chain (`scripts/kind-add-metallb.sh`, `scripts/migrate-from-metallb.sh`, `scripts/e2e-migrate-smoke.sh`, `scripts/kind-add-cloud-provider-kind.sh`, `scripts/e2e-smoke.sh`, `scripts/lib.sh`, the workflow file) (positive-include `paths:` filter is intentional — runs when its own or the shared smoke-chain code changes; the shared scripts are included so a fix that only breaks the MetalLB path, which `ci.yml`'s cloud-provider-kind `e2e` job doesn't exercise, isn't missed until the weekly cron). Mirrors the `e2e` job but installs **MetalLB** instead of cloud-provider-kind; same K1.5 route-readiness poll before `LB=metallb make e2e-smoke`. Final step runs `scripts/e2e-migrate-smoke.sh` to exercise the **MetalLB → cloud-provider-kind migration** path so regressions in `migrate-from-metallb.sh` surface here.
- **monitoring-test.yml** — weekly cron (Sunday 05:00 UTC) + `workflow_dispatch` + push on `scripts/kind-add-kube-prometheus-stack.sh` plus the shared smoke chain (`scripts/e2e-smoke.sh`, `scripts/lib.sh`, the workflow file — the `TEST_MONITORING` assertions live in `e2e-smoke.sh`, which `ci.yml` never runs with `TEST_MONITORING=yes`). Brings up the full stack via `make install-all` (cloud-provider-kind), installs `kube-prometheus-stack`, then runs `TEST_MONITORING=yes make e2e-smoke` to assert Grafana gets a LoadBalancer IP and the admin secret is mintable. Off the default install-all path — kept on its own cron to keep PR feedback fast.
- **registry-test.yml** — weekly cron (Sunday 06:00 UTC) + `workflow_dispatch` + push on registry-related files (`scripts/kind-with-registry.sh`, `scripts/test-registry.sh`, `scripts/lib.sh`, `k8s/helloweb-deployment-local.yaml`, the workflow file). Exercises the alternative `make registry` cluster (containerd-mirrored local registry at `localhost:5001`) via `make registry-test` (pull → retag → push → deploy → curl). Distinct from the install-all flow; separate workflow rather than another job.
- **gateway-test.yml** — weekly cron (Sunday 07:00 UTC) + `workflow_dispatch` + push on the gateway scripts/manifests + the shared smoke chain (`scripts/kind-add-gateway-*.sh`, `k8s/gateway/**`, `scripts/kind-add-traefik.sh`, `scripts/e2e-smoke.sh`, `scripts/lib.sh`, the workflow file). Brings up `make install-all`, then `make gateway-traefik` (Traefik's Gateway API provider) + `make gateway-istio` (Istio) + `make gateway-nginx` (NGINX Gateway Fabric) + `make gateway-contour` (Project Contour), then `TEST_GATEWAY_API=yes make e2e-smoke` to assert all controllers front the same demo apps. The shared Gateway API CRDs are the **experimental** channel (Contour requires `TLSRoute@v1alpha2`); HAProxy Ingress was evaluated but dropped (v0.16.1 crash-loops on GW API v1.5.1 — see `docs/gateway-api-ingress.md`). Off the default install-all path — Gateway API is opt-in.
- **cleanup-runs.yml** — weekly cron (Sunday midnight). Two jobs: `cleanup-runs` (prunes old runs, keeps latest 5) and `cleanup-caches` (deletes caches from closed PR branches).

### Paths that CI does NOT exercise

The following paths require resources GitHub-hosted runners can't reliably provide; they are verified manually before each release:

- **`make vm-up` / `make vm-install-all` (Multipass)** — nested virtualization isn't reliably supported on `ubuntu-24.04` GitHub-hosted runners; cloud-init bootstrap takes 3–5 minutes; CI cost outweighs catch rate. Verify locally before tagging a release.
- **`make nfs-host-setup`** — modifies `/etc/exports`, opens the firewall, requires interactive `sudo`. Out of scope for unattended CI. Verify locally on Ubuntu/Debian before tagging. The host-NFS provisioner has an opt-in smoke assertion gated behind `TEST_NFS_HOST=yes` (asserts the `nfs-host` StorageClass exists and `k8s/nfs/pvc.yaml`'s `demo-claim` PVC binds); it stays manual-only for the same reason — run `make nfs-host-setup && make nfs-host-provisioner NFS_SERVER=<ip>` then `TEST_NFS_HOST=yes make e2e-smoke`.

## Dependencies

Runtime (user provides): Docker, helm, curl, base64.

Pinned in [`.mise.toml`](./.mise.toml) and installed by `make deps` via [mise](https://mise.jdx.dev): `kind`, `kubectl`, `jq`, `shellcheck`, `actionlint`, `gitleaks`, `trivy`, `hadolint`, `act`, `bats`. `make deps` auto-bootstraps mise into `~/.local/bin` if missing, then runs `mise install` (idempotent; no-op at pinned versions).

Docker-image-pinned in Makefile (Renovate-tracked via inline `# renovate:` comments): `KUBECTL_VERSION` (shared with `images/Dockerfile` `--build-arg`; kept in sync with `aqua:kubernetes/kubectl` in `.mise.toml` via the `kubectl` packageRule), `MERMAID_CLI_VERSION`, `PLANTUML_VERSION`, `PUML2DRAWIO_VERSION`, `KIND_NODE_IMAGE`, `CLOUD_PROVIDER_KIND_VERSION`, `ACT_UBUNTU_VERSION` (catthehacker/ubuntu). `mermaid-cli` is invoked from `make mermaid-lint` (part of the `static-check` composite); `plantuml/plantuml` from `make diagrams` / `diagrams-check`.

No Go modules; no package manager lockfiles.

## Conventions and exceptions

- **MetalLB is intentionally retained** as an alternative LoadBalancer alongside cloud-provider-kind (the portfolio default). cloud-provider-kind is wired as primary in `make install-all`; MetalLB is opt-in via `LB=metallb make install-all` or `make lb-metallb`. The weekly `e2e-metallb.yml` cron exercises the MetalLB code path. Migration helper: `scripts/migrate-from-metallb.sh`.
- **Cluster name is parameterized via `KIND_CLUSTER_NAME`** (defaults to `kind` for backward compat with existing tooling and docs that reference the `kind-kind` context). Every script defines `KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")` and uses `"${KUBECTL[@]}"` for all kubectl invocations — a parallel `make` invocation in another KinD project that runs `kubectl config use-context` cannot silently switch this project's scripts to the wrong cluster. Override per-project to coexist on a single host: `KIND_CLUSTER_NAME=foo make install-all`. The `kubectl config use-context` call in `kind-create.sh` is the only place the kubeconfig's current-context is mutated. Registry cluster (`scripts/kind-with-registry.sh`) uses its own `CLUSTER_NAME` (default `kind-registry`) for the same reason.
- **`runs-on: ubuntu-24.04`** is the explicit pin (not `ubuntu-latest`) — avoids surprise migrations when GitHub flips the alias to a new LTS.
- **Suppression files**: `.gitleaks.toml`, `.trivyignore.yaml`, `.hadolint.yaml` — each annotates the specific rule waivers inline.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
