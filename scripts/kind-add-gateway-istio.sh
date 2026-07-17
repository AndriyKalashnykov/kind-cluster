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

# renovate: datasource=github-releases depName=istio/istio
ISTIO_VERSION=1.30.3
ISTIO_CHARTS="https://istio-release.storage.googleapis.com/charts"

# Gateway API CRDs first — Istio ≤1.29 + v1.5 CRDs crash-loops istiod; this repo
# pins Istio 1.30.x (supports Gateway API v1.5.x) so the order is the only gate.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing Istio ${ISTIO_VERSION} (base + istiod, minimal) ==="
helm repo add istio "$ISTIO_CHARTS" >/dev/null 2>&1 || true
helm repo update istio >/dev/null
"${HELM[@]}" upgrade --install istio-base istio/base \
    --version "${ISTIO_VERSION}" --namespace istio-system --create-namespace \
    --wait --timeout "${TIMEOUT}"
"${HELM[@]}" upgrade --install istiod istio/istiod \
    --version "${ISTIO_VERSION}" --namespace istio-system \
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
