#!/usr/bin/env bash
# Install Istio (minimal) as a SECOND Gateway API controller that coexists with
# Traefik and fronts the SAME demo apps via its own LoadBalancer IP. Istio is NOT
# a CNI — it installs over the existing kindnet cluster. For north-south ingress
# we do not mesh the app pods (no sidecar injection); applying a Gateway with
# gatewayClassName: istio auto-provisions a dedicated Envoy Deployment+Service.
#
# Requires `make install-all` first (cloud-provider-kind must be running so the
# auto-provisioned gateway Service gets an external IP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# Istio retired https://istio-release.storage.googleapis.com/charts: from 1.31 on,
# charts are published ONLY to blob.istio.io, and the old bucket is deleted in
# December 2026 (istio.io/latest/blog/2026/retirement-of-gcp/). Its index froze at
# 2026-08-27, so base-1.31.0.tgz 404s there while it is HTTP 200 on blob.istio.io.
# registryUrl MUST point at the live index or Renovate reads the frozen one, sees
# 1.30.4 as newest, and silently never opens another PR.
# Attribute order is load-bearing: datasource depName [extractVersion] [registryUrl].
# renovate: datasource=helm depName=base registryUrl=https://blob.istio.io/istio-release/charts
ISTIO_VERSION=1.31.0
ISTIO_CHARTS="https://blob.istio.io/istio-release/charts"

# Gateway API CRDs first — a too-old Istio against newer CRDs crash-loops istiod
# (Istio ≤1.29 + v1.5 CRDs). Istio 1.31.0 vendors sigs.k8s.io/gateway-api v1.6.0
# against this repo's v1.6.2 CRDs; keep this pin moving with the CRD channel.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing Istio ${ISTIO_VERSION} (base + istiod, minimal) ==="
# Direct chart tarball URLs — bypasses `helm repo add`+index.yaml, matching the
# pattern kind-add-traefik.sh already uses, so an upstream index restructure cannot
# break the install silently. It also sidesteps `helm repo add ... || true`, which
# swallows the "repository name already exists" error a URL change raises and would
# leave a developer's stale alias pointing at the retired bucket.
"${HELM[@]}" upgrade --install istio-base "${ISTIO_CHARTS}/base-${ISTIO_VERSION}.tgz" \
    --namespace istio-system --create-namespace \
    --wait --timeout "${TIMEOUT}"
"${HELM[@]}" upgrade --install istiod "${ISTIO_CHARTS}/istiod-${ISTIO_VERSION}.tgz" \
    --namespace istio-system \
    --wait --timeout "${TIMEOUT}"
"${KUBECTL[@]}" -n istio-system rollout status deployment/istiod --timeout="${TIMEOUT}"

echo "=== Applying Istio Gateway + HTTPRoutes (auto-provisions an Envoy gateway) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/istio-gateway.yaml
# Applying the Gateway (gatewayClassName: istio) auto-creates Deployment+Service
# named "<gateway>-<class>" = "istio-istio" in the default namespace.
"${KUBECTL[@]}" -n default rollout status deployment/istio-istio --timeout="${TIMEOUT}"

echo "Istio Gateway API installed. Its gateway Service gets its own LoadBalancer IP:"
"${KUBECTL[@]}" -n default get svc istio-istio \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via Istio, e.g.:"
echo "  IP=\$(kubectl -n default get svc istio-istio -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
