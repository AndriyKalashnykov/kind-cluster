# Gateway API & ingress controllers in this cluster

> How `kind-cluster` exposes HTTP services, why the Kubernetes **Gateway API** is
> the strategic successor to classic **Ingress**, and a fact-checked comparison of
> three Gateway API implementations — **Traefik**, **Istio**, and a
> CNI-integrated option (**Cilium** / **Calico**) — including how to run more than
> one of them in the same cluster.
>
> Every version, conformance status, and behaviour below is cited to a primary
> source (see [References](#references)). Verified 2026-06-06 against Gateway API
> **v1.5.1**, Traefik chart **40.2.0** (appVersion **v3.7.1**), Istio **1.30.1**,
> Cilium **v1.19.4**, Calico **v3.32.0**.

## TL;DR

- The project's **default** path is still **classic Ingress** (`networking.k8s.io/v1`,
  `ingressClassName: traefik`) — see [`k8s/demo-apps-ingress.yaml`](../k8s/demo-apps-ingress.yaml).
  It is the simplest thing that works and stays the zero-config default.
- The **Gateway API** is the future: the Ingress API is feature-frozen, and the
  reference `ingress-nginx` controller is **retiring** (best-effort maintenance
  ends March 2026) — which is why this project already moved to **Traefik**.
  Gateway API is **GA** (v1.0 in Oct 2023; current **v1.5.1**).
- Traefik v3 and Istio are both **conformant Gateway API controllers**. You can
  enable them here opt-in:
  - `make gateway-traefik` — turns on Traefik's Gateway API provider and routes
    the **same** demo apps through a `Gateway` + `HTTPRoute`s (no extra workload —
    same Traefik pod also keeps serving classic Ingress).
  - `make gateway-istio` — installs Istio (minimal) as a **second** Gateway API
    controller that coexists with Traefik and fronts the **same** demo apps via
    its own LoadBalancer IP.
- **Antrea is not in this comparison.** Antrea is a **CNI**, not a Gateway API
  controller — its "gateway" (`antrea-gw0`) is an Open vSwitch dataplane interface,
  unrelated to `gateway.networking.k8s.io`. If you want a **CNI-integrated**
  gateway, the real options are **Cilium** or **Calico** (both conformant) — see
  [§ CNI-integrated gateways](#cni-integrated-gateways-cilium--calico).

---

## Ingress vs Gateway API

Classic **Ingress** (`networking.k8s.io/v1`) is a single, controller-specific
resource: one object holds host/path rules, and everything beyond plain HTTP
host/path routing (TLS options, header rewrites, traffic splitting, gRPC, TCP)
lives in **controller-specific annotations**. That annotation sprawl, plus a lack
of role separation, is why the Ingress API was frozen and the community built a
replacement.

The **Gateway API** (`gateway.networking.k8s.io`) is a role-oriented, typed
replacement, GA since v1.0:

| Resource | Owned by | Purpose |
|----------|----------|---------|
| **GatewayClass** | infrastructure provider | Names a controller via `controllerName` (like a `StorageClass` for gateways) |
| **Gateway** | cluster operator | A concrete data-plane listener (ports, protocols, TLS) bound to one GatewayClass |
| **HTTPRoute** / GRPCRoute / TCPRoute / TLSRoute | app developer | Routing rules: `parentRefs` (which Gateways) + `backendRefs` (which Services) |

Two properties matter for everything below:

1. **`GatewayClass.spec.controllerName` selects the controller.** Each controller
   *"MUST watch all GatewayClasses, and reconcile GatewayClasses that have a
   matching controllerName"* — and ignores the rest. This is what lets multiple
   controllers coexist (see [§ Running more than one](#running-more-than-one-controller)).
2. **An `HTTPRoute` references a Gateway (`parentRefs`) and Services
   (`backendRefs`) independently.** The same backend Service can be fronted by
   many routes under different Gateways — which is how two controllers route to
   the *same* app.

**Channels.** Gateway API ships a **standard** channel (GA: GatewayClass,
Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, BackendTLSPolicy) and an
**experimental** channel (TCPRoute, TLSRoute, UDPRoute, …). Install one or the
other CRD set:

```bash
# standard (GA) channel
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
# experimental channel (adds TCPRoute/TLSRoute/UDPRoute)
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml
```

> The CRDs are **not** bundled by Traefik's or Istio's charts — they must be
> applied first. The project's `make gateway-*` targets do this for you (pinned,
> Renovate-tracked).

---

## The implementations

All three rows below are **conformant** Gateway API controllers on the official
[implementations registry](https://gateway-api.sigs.k8s.io/implementations/)
(checked 2026-06): Traefik Proxy (v1.5.1), Istio (v1.4.0), Cilium (v1.5.1), Calico (v1.4.1).

| | **Traefik** (this project's default proxy) | **Istio** | **Cilium / Calico** (CNI-integrated) |
|---|---|---|---|
| **What it is** | Standalone L7 reverse proxy / ingress controller | Service mesh + ingress (Envoy data plane) | A **CNI** that *also* implements Gateway API |
| **`controllerName`** | `traefik.io/gateway-controller` | `istio.io/gateway-controller` | `cilium` (GatewayClass) / Calico via Tigera operator |
| **GatewayClass name** | `traefik` (chart can auto-create) | `istio` (built-in; also `istio-remote`, `istio-waypoint`, `istio-east-west`) | `cilium` / a default class from the operator |
| **Deployment model** | In-process provider in the **existing single Traefik pod** — no extra workload | `istiod` control plane **+ one Envoy Deployment+Service auto-provisioned per `Gateway`** (named `<gateway>-<class>`) | Built into the CNI agent/operator (Cilium: built-in Envoy; Calico: Envoy Gateway) |
| **Footprint** | None beyond Traefik (already running) | Heaviest: `istiod` + per-gateway Envoy (sidecar Envoy ≈ 0.2 vCPU / 60 MB at 1k req/s; `istiod` scales with config — Istio docs give no fixed number) | CNI-level; replaces kindnet |
| **Channels** | HTTPRoute, GRPCRoute, BackendTLSPolicy (standard); TCPRoute + **TLSRoute via `experimentalChannel`** | HTTPRoute (standard); experimental routes supported | varies |
| **Install onto a running kind cluster?** | ✅ yes (already installed) | ✅ yes (over the existing CNI — Istio is **not** a CNI) | ❌ no — a CNI is chosen at **cluster creation** (`disableDefaultCNI`), i.e. a cluster recreate |
| **Best for** | Lightweight north-south ingress; the default here | North-south ingress **and** east-west mesh (GAMMA); advanced traffic management | One dataplane for pod networking **and** L7 gateway (eBPF / Envoy) |

### Traefik (Gateway API mode)

Traefik v3 has shipped a production-ready Gateway API provider since v3.1 and is
conformant at Gateway API **v1.5.1**. In this project it is **already running**
as a classic Ingress controller; the Gateway API provider is a second,
independent in-process provider — enabling it does **not** disable Ingress, and
adds **no new pod**. Enable in the Helm chart with:

```
--set providers.kubernetesGateway.enabled=true
# optionally: --set providers.kubernetesGateway.experimentalChannel=true   # TCPRoute/TLSRoute
```

The chart can also auto-create a default `traefik` GatewayClass and a default
`Gateway` (`gatewayClass.enabled` / `gateway.enabled`). `make gateway-traefik`
enables the provider and applies the demo `Gateway` + `HTTPRoute`s.

> ⚠️ **`TLSRoute` is an experimental-channel resource.** Traefik v3 supports it,
> but it needs the `experimental-install.yaml` CRDs **and**
> `providers.kubernetesGateway.experimentalChannel=true`. (`HTTPRoute` and
> `GRPCRoute` are standard-channel and need neither.)

### Istio (Gateway API mode)

Istio is a conformant Gateway API controller (`istio.io/gateway-controller`,
GatewayClass `istio`). Key facts for a kind lab:

- **It is not a CNI** — *"ambient mode is not a CNI itself — it runs over existing
  CNIs."* Istio installs onto the running kindnet cluster fine.
- For **north-south ingress only**, you do **not** need to mesh the app pods (no
  sidecar injection, no ambient enrollment). Applying a `Gateway` with
  `gatewayClassName: istio` **auto-provisions** an Envoy `Deployment` + `Service`
  named `<gateway>-istio`; that Service is `LoadBalancer`, so cloud-provider-kind
  gives it its own IP.
- **CRDs must be installed first, and version-compatible** — Istio ≤ 1.29 +
  Gateway API v1.5 CRDs makes `istiod` crash-loop (analyzer check `IST0176`).
  This project pins Istio **1.30.1**, which supports v1.5.x CRDs.
- **GAMMA** (Gateway API for Mesh) extends the same API to **east-west** traffic
  by setting an HTTPRoute's `parentRef` to a **Service** instead of a Gateway —
  out of scope here (we only wire north-south ingress), but it's why Istio is
  more than "another ingress."

`make gateway-istio` installs the Gateway API CRDs + Istio (minimal, via the
official Helm charts — `base` + `istiod`, no app meshing), then applies an Istio
`Gateway` + `HTTPRoute`s for the same demo apps.

### CNI-integrated gateways (Cilium / Calico)

If the interest is a **single dataplane that does both pod networking and L7
gateway**, the real options are **Cilium** and **Calico** — both on the Gateway
API conformance list:

- **Cilium** — eBPF CNI with built-in Gateway API (GatewayClass `cilium`), served
  by an embedded **Envoy**; requires kube-proxy replacement and an LB/L2 path.
- **Calico** — its **Calico Ingress Gateway** is a hardened distribution of the
  **Envoy Gateway** project — enabled cluster-wide via the Tigera operator's
  `GatewayAPI` installation CR, then provisioned per-gateway from a standard
  `Gateway` resource.

**These cannot be "added" to the running cluster.** A cluster has exactly one
CNI, and kind installs `kindnetd` by default; switching CNIs is a
**cluster-creation-time** decision. To try Cilium here you recreate the cluster
with the default CNI disabled:

```yaml
# kind config — disable kindnet so a real CNI can own pod networking
networking:
  disableDefaultCNI: true
  podSubnet: "10.244.0.0/16"
```

```bash
kind create cluster --config kind-cilium.yaml
cilium install --version 1.19.4 --set kubeProxyReplacement=true \
  --set gatewayAPI.enabled=true        # requires Gateway API CRDs pre-applied
```

This is a different (heavier) experiment than the Traefik-vs-Istio comparison,
which is why this repo documents it rather than wiring it into `install-all`. The
kind docs note `disableDefaultCNI` is *"a power user feature with limited
support, but many common CNI manifests are known to work, e.g. Calico."*

### Why not Antrea?

A common confusion worth stating plainly: **Antrea is a CNI, not a Gateway API
controller.** It is **not** on the Gateway API implementations list; the
`antrea-io/antrea` repo has no `sigs.k8s.io/gateway-api` dependency and no
`GatewayClass`/`HTTPRoute` controller. The thing called the **"Antrea gateway"**
is `antrea-gw0` — *"an internal port … to be the gateway of the Node's subnet"* —
an **Open vSwitch dataplane interface** for pod/node traffic, entirely unrelated
to `gateway.networking.k8s.io`. Antrea's L7 features (L7 NetworkPolicy — which is
**Suricata**-based, not Envoy; AntreaProxy; Egress) are east-west CNI features,
not a north-south HTTP gateway. If you saw "Antrea gateway" and expected the
Kubernetes Gateway API, that's the lexical trap. For a **CNI-integrated gateway**
use Cilium or Calico; for a fair **CNI/NetworkPolicy** comparison, Antrea belongs
next to Cilium/Calico/kindnet — a different axis than this document.

---

## Running more than one controller

> *Can Traefik + Istio coexist and route to the **same** apps? Yes. Is it
> advisable? For a comparison lab, yes — with the caveats below.*

**1. No API-level conflict.** Each controller reconciles only Gateways whose
GatewayClass `controllerName` matches its own. `traefik.io/gateway-controller`
and `istio.io/gateway-controller` are distinct, so the `traefik` and `istio`
GatewayClasses coexist and each controller ignores the other's Gateways.

**2. Same app, two front doors.** An `HTTPRoute` names its Gateway in
`parentRefs` and its Services in `backendRefs`; nothing ties a Service to one
route. So `demo-route-traefik` (→ Traefik Gateway) and `demo-route-istio`
(→ Istio Gateway) can both carry `backendRefs: helloweb` — both gateways front
the identical pods.

**3. The only real contention is the entry-point address:**

- **hostPort 80/443 is single-binding.** Traefik already occupies the
  control-plane node's host ports 80/443 (via `kind-config.yaml`
  `extraPortMappings`). A second controller **cannot** also bind them.
- **cloud-provider-kind gives each `LoadBalancer` Service its own IP** from the
  kind docker bridge (one `kindccm-…` Envoy container per Service). So Istio's
  auto-provisioned gateway Service gets a **distinct** IP.

So you reach **Traefik** at `http://localhost/` (hostPort) and **Istio** at its
own `http://<istio-LB-IP>/` — same backends, different doors. No collision.

```
                         ┌─────────────────────── same backend Services ───────────────────────┐
                         │            helloweb         golang-web         foo-service           │
                         └───────▲───────────────────────▲──────────────────────▲──────────────┘
        HTTPRoute(parent=traefik)│                        │ HTTPRoute(parent=istio)
                ┌────────────────┴───────┐        ┌───────┴──────────────────┐
   host :80 ───▶│ Traefik  (class traefik)│        │ Istio gw (class istio)   │◀── LB IP (cloud-provider-kind)
   (hostPort)   │ controllerName:          │        │ controllerName:          │
                │ traefik.io/gw-controller │        │ istio.io/gw-controller   │
                └──────────────────────────┘        └──────────────────────────┘
```

### Is it advisable to install all of them?

- **Traefik + Istio (Gateway API):** ✅ fine for a comparison lab — distinct
  GatewayClass, distinct entry IP, same backends. Istio adds real weight
  (`istiod` + a per-gateway Envoy), so it's opt-in, not part of `install-all`.
- **A third "Antrea gateway":** ❌ not a thing — Antrea is a CNI (see above).
- **Cilium/Calico (CNI gateway):** ⚠️ a **separate cluster** — a CNI is chosen at
  creation time and is mutually exclusive with kindnet (and with each other). You
  don't run it *alongside*; you recreate the cluster with it.

---

## How this project wires it

| Target | What it does | Reach it at |
|--------|--------------|-------------|
| `make ingress-traefik` | **Default.** Traefik as a classic Ingress controller (`ingressClassName: traefik`), hostPort 80/443 | `http://<app>.localdev.me/` via `localhost` |
| `make gateway-traefik` | Opt-in. Installs Gateway API CRDs (pinned), enables Traefik's Gateway API provider, applies a `Gateway` + `HTTPRoute`s for the demo apps on `*.gw.localdev.me` | `curl -H 'Host: helloweb.gw.localdev.me' http://localhost/` (same Traefik hostPort, now also via Gateway API) |
| `make gateway-istio` | Opt-in. Installs Gateway API CRDs + Istio (minimal) + an Istio `Gateway` + `HTTPRoute`s for the **same** demo apps on the original `*.localdev.me` hosts | `curl -H 'Host: helloweb.localdev.me' http://<istio-gateway-LB-IP>/` |

Both `gateway-*` targets are idempotent on the shared Gateway API CRDs
(install-if-absent), require **cloud-provider-kind** to be running (for LB IPs),
and route to the **existing** demo Services — so you can enable either or both on
a cluster brought up with `make install-all` and compare them side by side.
Smoke coverage for the Gateway API paths is gated behind `TEST_GATEWAY_API=yes`
(see [`scripts/e2e-smoke.sh`](../scripts/e2e-smoke.sh)).

---

## References

Gateway API
- Implementations registry — <https://gateway-api.sigs.k8s.io/implementations/>
- GatewayClass / HTTPRoute references — <https://gateway-api.sigs.k8s.io/reference/api-types/gatewayclass/> · <https://gateway-api.sigs.k8s.io/reference/api-types/httproute/>
- Implementer's Guide (controllerName reconcile rule) — <https://gateway-api.sigs.k8s.io/guides/implementers/>
- Kubernetes concept — <https://kubernetes.io/docs/concepts/services-networking/gateway/>
- Releases (v1.5.1) — <https://github.com/kubernetes-sigs/gateway-api/releases>

Traefik
- Gateway API routing reference — <https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/>
- Enable the provider / install CRDs — <https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/>
- Helm chart values — <https://github.com/traefik/traefik-helm-chart/blob/master/traefik/values.yaml>

Istio
- Kubernetes Gateway API task — <https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/>
- Getting started with Gateway API (controllerName) — <https://istio.io/latest/blog/2022/getting-started-gtwapi/>
- GAMMA / mesh — <https://gateway-api.sigs.k8s.io/mesh/> · <https://istio.io/latest/blog/2024/gateway-mesh-ga/>
- Performance & scalability — <https://istio.io/latest/docs/ops/deployment/performance-and-scalability/>

CNI-integrated gateways
- Cilium Gateway API — <https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/>
- Calico Gateway API — <https://docs.tigera.io/calico/latest/networking/gateway-api>

Antrea (why it's not a Gateway API controller)
- Architecture / the `antrea-gw0` gateway port — <https://antrea.io/docs/main/docs/design/architecture/>
- L7 NetworkPolicy (Suricata-based) — <https://antrea.io/docs/main/docs/antrea-l7-network-policy/>
- Antrea on kind (CNI swap) — <https://antrea.io/docs/main/docs/kind/>

kind / LoadBalancer
- LoadBalancer (cloud-provider-kind) — <https://kind.sigs.k8s.io/docs/user/loadbalancer/>
- Configuration (`disableDefaultCNI`, `extraPortMappings`) — <https://kind.sigs.k8s.io/docs/user/configuration/>
- cloud-provider-kind — <https://github.com/kubernetes-sigs/cloud-provider-kind>
