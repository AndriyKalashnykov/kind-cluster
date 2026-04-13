[![End to End Tests](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml/badge.svg)](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/kind-cluster.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/kind-cluster/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/kind-cluster)

# kind-cluster

Shell-script toolkit for provisioning local Kubernetes clusters with [KinD](https://kind.sigs.k8s.io/) and installing common cluster add-ons (Nginx ingress, MetalLB, Kubernetes Dashboard, NFS provisioner, Prometheus stack) plus demo workloads.

| Component | Technology |
|-----------|-----------|
| Cluster | [KinD](https://kind.sigs.k8s.io/) on Docker |
| Ingress | [ingress-nginx](https://kubernetes.github.io/ingress-nginx/) |
| Load Balancer | [MetalLB](https://metallb.universe.tf/) |
| Storage (RWX) | [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) (in-cluster) or [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) (host-backed) |
| Observability | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) |
| Dashboard | [Kubernetes Dashboard](https://github.com/kubernetes/dashboard) |
| CI | GitHub Actions (`helm/kind-action`) |

## Quick Start

```bash
make deps        # verify required tools are installed
make kind-up     # create cluster + Nginx ingress + MetalLB + demo workloads
kubectl cluster-info --context kind-kind
# Open http://demo.localdev.me/
make kind-down   # tear down
```

`kind-up` is a docker-compose-style alias for `install-all`. For the cluster and add-ons without the demo apps, run `make install-all-no-demo-workloads`.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Task orchestration |
| [Git](https://git-scm.com/) | latest | Version control |
| [Docker](https://www.docker.com/) | latest | Container runtime for KinD nodes |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start#installation) | v0.14.0+ | Local Kubernetes in Docker |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.25.0+ | Kubernetes CLI |
| [helm](https://helm.sh/docs/intro/install/) | v3+ | Chart-based installs (dashboard, Prometheus, NFS) |
| [curl](https://curl.se/) | latest | Download helpers used by scripts |
| [jq](https://github.com/jqlang/jq) | latest | JSON parsing in scripts |
| [base64](https://command-not-found.com/base64) | latest | Token decoding for dashboard access |

## Available Make Targets

Run `make help` to list targets.

### Cluster Lifecycle

| Target | Description |
|--------|-------------|
| `make kind-up` | docker-compose-style alias for `install-all` (bring the whole stack up) |
| `make kind-down` | docker-compose-style alias for `delete-cluster` (tear the whole stack down) |
| `make install-all` | Create cluster + Nginx ingress + MetalLB + demo workloads (granular) |
| `make install-all-no-demo-workloads` | Create cluster + Nginx ingress + MetalLB (no demo apps) |
| `make create-cluster` | Create KinD cluster (granular) |
| `make delete-cluster` | Delete KinD cluster (granular) |
| `make export-cert` | Export k8s client keys and CA certificates |

### Cluster Add-ons

| Target | Description |
|--------|-------------|
| `make dashboard-install` | Install Kubernetes Dashboard (Helm chart v7.14.0) + admin ServiceAccount |
| `make dashboard-forward` | Port-forward dashboard to `https://localhost:8443` and open browser |
| `make dashboard-token` | Print the admin-user token |
| `make nginx-ingress` | Install Nginx ingress controller |
| `make metallb` | Install MetalLB load balancer |
| `make metrics-server` | Install metrics-server (for `kubectl top` / HPA) |
| `make kube-prometheus-stack` | Install Prometheus + Grafana + Alertmanager |

### Virtual Ubuntu Host (Multipass)

| Target | Description |
|--------|-------------|
| `make vm-up` | Launch Ubuntu 22.04 VM via Multipass, cloud-init provisions Docker + kind + kubectl + helm + nfs-kernel-server |
| `make vm-ssh` | Open interactive shell inside the VM |
| `make vm-install-all` | Run `make install-all` inside the VM (remote bootstrap) |
| `make vm-down` | Stop, delete, and purge the VM |

### RWX Storage (NFS)

| Target | Description |
|--------|-------------|
| `make nfs-incluster` | Option 1 — in-cluster NFS server + csi-driver-nfs (no host config) |
| `make nfs-host-setup` | Option 2, step 1 — configure HOST as NFS server (sudo, Ubuntu/Debian) |
| `make nfs-host-provisioner NFS_SERVER=<ip>` | Option 2, step 2 — install `nfs-subdir-external-provisioner` pointing at the host |

### Demo Workloads

| Target | Description |
|--------|-------------|
| `make deploy-app-nginx-ingress-localhost` | Deploy httpd with ingress rule at `http://demo.localdev.me/` |
| `make deploy-app-helloweb` | Deploy helloweb sample app |
| `make deploy-app-golang-hello-world-web` | Deploy golang-hello-world-web sample app |
| `make deploy-app-foo-bar-service` | Deploy foo-bar-service sample app |

### Utilities

| Target | Description |
|--------|-------------|
| `make deps` | Verify required tools are installed |
| `make image-build` | Build `kubectl-test` Docker image (from `images/Dockerfile`) |
| `make renovate-validate` | Validate `renovate.json` configuration |

## k8s Dashboard

Pinned to Helm chart [`kubernetes-dashboard`](https://github.com/kubernetes/dashboard) **v7.14.0**. Dashboard v7 splits the monolithic v2 service into microservices (`api`, `web`, `auth`, `metrics-scraper`) behind a **Kong Gateway** reverse proxy — you port-forward the `kong-proxy` Service, not a pod.

```mermaid
flowchart LR
    B[Browser<br/>https://localhost:8443] -->|kubectl port-forward| K[Service<br/>kubernetes-dashboard-kong-proxy]
    K --> W[web]
    K --> A[api]
    K --> U[auth]
    K --> M[metrics-scraper]
```

```bash
make dashboard-install   # helm upgrade --install + apply admin ServiceAccount + write token to dashboard-admin-token.txt
make dashboard-forward   # kubectl port-forward svc/kubernetes-dashboard-kong-proxy 8443:443 + xdg-open
make dashboard-token     # print the admin-user token
```

At the login screen, select **Token** and paste the token printed by `make dashboard-token`.

Uninstall: `helm delete kubernetes-dashboard --namespace kubernetes-dashboard`.

## NFS & RWX storage

Kubernetes default storage classes only support `ReadWriteOnce` (a PV can be mounted by a single node). To run workloads that need `ReadWriteMany` (multiple pods writing to the same volume) — e.g., CI shared caches, content-processing pipelines, WordPress clusters — you need an NFS-backed StorageClass.

Two approaches are provided. Pick one.

### Option 1 — in-cluster NFS (recommended for local dev)

An NFS server runs as a pod inside the cluster. [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) provisions PVs backed by that pod. **No host config, no sudo, no `/etc/exports`.** Tears down cleanly with the cluster; data does not survive `make kind-down`.

```mermaid
flowchart LR
    A[app pod] -->|RWX PVC<br/>storageClassName: nfs-csi| SC[StorageClass<br/>nfs-csi]
    SC --> CSI[csi-driver-nfs<br/>kube-system]
    CSI -->|NFSv4.1| NS[nfs-server pod<br/>namespace: nfs-server]
    NS --> ED[(emptyDir<br/>ephemeral)]
```

```bash
make nfs-incluster
kubectl apply -f ./k8s/nfs/pvc-incluster.yaml   # sample RWX PVC
```

Pinned versions: `csi-driver-nfs` v4.13.1. Source: `scripts/kind-add-nfs-incluster.sh`.

### Option 2 — host-side NFS (persistent across cluster recreates)

The **host machine** runs `nfs-kernel-server` and exports a directory; [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) inside the cluster provisions PVs backed by that host export. Data survives cluster teardown — useful when you want state to outlive `kind-down`. Requires sudo on the host and only works on Linux.

```mermaid
flowchart LR
    A[app pod] -->|RWX PVC<br/>storageClassName: nfs-client| SC[StorageClass<br/>nfs-client]
    SC --> P[nfs-subdir-external-provisioner<br/>namespace: nfs-provisioning]
    P -.NFSv4.-> HOST[host NFS server<br/>/mnt/k8s_nfs_storage]
    HOST --> DISK[(host disk<br/>persistent)]
```

```bash
# 1. Host-side: install nfs-kernel-server, create export, open firewall (interactive sudo)
make nfs-host-setup

# 2. In-cluster: install the provisioner pointing at the host (replace NFS_SERVER with your host IP)
make nfs-host-provisioner NFS_SERVER=192.168.1.27
kubectl apply -f ./k8s/nfs/pvc.yaml             # sample RWX PVC
```

Pinned versions: `nfs-subdir-external-provisioner` chart 4.0.18. Sources: `scripts/kind-add-nfs-host-setup.sh`, `scripts/kind-add-nfs-host-provisioner.sh`.

**References:** [NFS Server on Ubuntu](https://www.tecmint.com/install-nfs-server-on-ubuntu/) · [Dynamic NFS Provisioning in k8s](https://www.linuxtechi.com/dynamic-nfs-provisioning-kubernetes/) · [RWX in KinD with NFS](https://cloudyuga.guru/hands_on_lab/nfs-kind).

## Run in a VM (Multipass)

For full reproducibility — and to keep Docker, kind, and the host NFS server off your main machine — the whole stack can run inside a throwaway Ubuntu VM. [Multipass](https://multipass.run/) ships the image, and a cloud-init YAML does the bootstrap.

```mermaid
flowchart LR
    DEV[Developer<br/>laptop]
    subgraph VM[Multipass VM: kind-host]
      D[Docker] --> K[KinD cluster<br/>control-plane + worker]
      NFS[nfs-kernel-server<br/>/srv/k8s_nfs_storage]
      K -->|Option 2| NFS
    end
    DEV -->|make vm-ssh| VM
    DEV -.forwarded ports.-> K
```

### 1. Install Multipass

| Platform | Install command | Notes |
|----------|-----------------|-------|
| Ubuntu / Debian / other Linux with snap | `sudo snap install multipass` | Uses snap confinement; nested virtualization works on KVM-capable hosts |
| macOS (Apple Silicon / Intel) | `brew install --cask multipass` | Uses `hypervisor.framework` on M1/M2/M3 |
| Windows 10/11 | `winget install Canonical.Multipass` or [direct download](https://multipass.run/download/windows) | Requires Hyper-V (Pro/Enterprise) or VirtualBox |

Verify: `multipass version` should print a version string and the daemon should be reachable (`multipass list` returns a table, even if empty).

Other install methods and troubleshooting: <https://multipass.run/install>.

### 2. Launch the VM

```bash
make vm-up                                # defaults: 4 CPU / 8 GB RAM / 40 GB disk
# or override:
make vm-up CPUS=6 MEMORY=12G DISK=60G NAME=my-kind
```

First boot takes ~3–5 min (Ubuntu cloud image download, apt-get install, docker pull, kind/kubectl/helm fetch). Subsequent `vm-up` on the same `NAME` is a no-op — the command prints `VM already exists` and shows `multipass info`.

The cloud-init playbook (`vm/cloud-init.yaml`) runs once at first boot:

1. Installs Docker CE, KinD v0.31.0, kubectl v1.35.1, helm v3.19.0
2. Installs `nfs-kernel-server`, exports `/srv/k8s_nfs_storage`
3. Clones this repo to `/home/ubuntu/kind-cluster`
4. Writes `/var/lib/kind-cluster-bootstrapped` as the finished sentinel — `vm-up.sh` polls this file.

### 3. Run the stack

```bash
# Option A: interactive — SSH in, then run inside
make vm-ssh
cd ~/kind-cluster && make install-all

# Option B: remote one-shot (git pulls latest + runs install-all)
make vm-install-all
```

### 4. Access services from your host

The VM has its own IP (`multipass info $NAME` → `IPv4`). MetalLB `LoadBalancer` IPs (helloweb, golang-hello-world-web, foo-bar-service) live on the VM's internal `kind` docker network and are **not routable from your laptop** out of the box.

Three options, simplest first:

**a. Exec into the VM and curl from there** (no host plumbing)

```bash
multipass exec $NAME -- bash -lc 'curl -s -H "Host: demo.localdev.me" http://localhost/'
multipass exec $NAME -- bash -lc 'kubectl get svc -A | grep LoadBalancer'
multipass exec $NAME -- bash -lc 'curl -s http://<LB_IP>:8080/myhello/'
```

**b. SSH port-forward individual services to your laptop**

```bash
make vm-ssh   # inside the VM:
kubectl port-forward svc/helloweb 8080:80 --address 0.0.0.0
# on the host: open http://<VM_IPv4>:8080
```

**c. Kubernetes Dashboard** — forwards to `localhost:8443` *inside* the VM. To reach it from the host, tunnel over SSH:

```bash
make vm-ssh                                    # terminal 1 — inside the VM:
make dashboard-forward                         # serves https://localhost:8443 in the VM
ssh -L 8443:localhost:8443 ubuntu@<VM_IPv4>    # terminal 2 — on the host
# Browser: https://localhost:8443
multipass exec $NAME -- bash -lc 'cd ~/kind-cluster && make dashboard-token'
```

Demo endpoints once installed:

| App | URL (inside VM) | Port |
|-----|-----------------|------|
| httpd + ingress | `http://demo.localdev.me/` | 80 |
| helloweb | `http://<LB_IP>/` | 80 |
| golang-hello-world-web | `http://<LB_IP>:8080/myhello/` · `/healthz` | 8080 |
| foo-bar-service | `http://<LB_IP>:5678/` | 5678 |
| Kubernetes Dashboard | `https://localhost:8443` (after `make dashboard-forward`) | 8443 |

### 5. Tear down

```bash
make vm-down
```

Runs `multipass stop && multipass delete && multipass purge` — no stale VMs left behind.

Override `NAME` to target a specific VM: `make vm-down NAME=my-kind`.

## Observability

### kube-prometheus-stack (Prometheus + Grafana + Alertmanager)

```bash
make kube-prometheus-stack
```

The script installs the community [`kube-prometheus-stack`](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) Helm chart into the `monitoring` namespace, patches the `grafana` Service to `LoadBalancer` (served via MetalLB), and prints the Grafana URL and admin credentials.

Default Grafana login: **admin / prom-operator**.

### metrics-server

Required for `kubectl top` and HorizontalPodAutoscalers. On KinD, the default manifest is patched with `--kubelet-insecure-tls` (the KinD kubelet serving cert isn't signed by the cluster CA).

```bash
make metrics-server
```

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **test-e2e** | push, PR, tags | Spin up KinD via `helm/kind-action`, install ingress + MetalLB + dashboard, deploy all demo workloads, curl-verify each via `docker exec` into the kind control-plane (~3.5 min end-to-end) |

A separate `cleanup-runs.yml` workflow prunes old workflow runs on a weekly schedule (Sunday midnight).

No repo secrets or variables are required by the workflow — only the default `GITHUB_TOKEN`.

[Renovate](https://docs.renovatebot.com/) keeps action digests, container images, and tool versions pinned in `Makefile` / `scripts/*.sh` (via `# renovate:` inline comments) up to date with platform automerge enabled.
