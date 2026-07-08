#!/usr/bin/env bash
# Install kgateway (the CNCF project, formerly Gloo Gateway OSS) as a Gateway API
# controller that coexists with Traefik, Istio, NGINX Gateway Fabric and Contour
# and fronts the SAME demo apps via its own LoadBalancer IP. kgateway is NOT a
# CNI — it installs over the existing kindnet cluster. Applying a Gateway with
# gatewayClassName: kgateway auto-provisions an Envoy data-plane Deployment+Service
# named after the Gateway (here "kgw") in the Gateway's namespace.
#
# kgateway v2.3.x vendors sigs.k8s.io/gateway-api v1.5.1 — the EXACT version this
# repo installs — so it deserializes the v1.5.1 GatewayClass.status.supportedFeatures
# object-list natively (immune to the crash that dropped HAProxy Ingress). Its own
# CRD chart ships ONLY gateway.kgateway.dev CRDs (it never touches the shared
# gateway.networking.k8s.io CRDs). See docs/gateway-api-ingress.md.
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

# renovate: datasource=github-releases depName=kgateway-dev/kgateway
KGATEWAY_VERSION=v2.3.5
KGATEWAY_CRDS_CHART="oci://cr.kgateway.dev/kgateway-dev/charts/kgateway-crds"
KGATEWAY_CHART="oci://cr.kgateway.dev/kgateway-dev/charts/kgateway"

# Shared Gateway API CRDs first (idempotent). kgateway v2.3.3 vendors Gateway API
# v1.5.1 exactly; the shared experimental-channel CRDs (a superset of standard)
# satisfy it.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing kgateway ${KGATEWAY_VERSION} (CRDs + control plane) ==="
# kgateway's OWN policy CRDs (gateway.kgateway.dev/*) — a separate chart that
# does NOT include or clobber the shared gateway.networking.k8s.io CRDs.
"${HELM[@]}" upgrade --install kgateway-crds "$KGATEWAY_CRDS_CHART" \
    --version "${KGATEWAY_VERSION}" --namespace kgateway-system --create-namespace \
    --wait --timeout "${TIMEOUT}"
"${HELM[@]}" upgrade --install kgateway "$KGATEWAY_CHART" \
    --version "${KGATEWAY_VERSION}" --namespace kgateway-system \
    --wait --timeout "${TIMEOUT}"

echo "=== Applying kgateway Gateway + HTTPRoutes (auto-provisions an Envoy data plane) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/kgateway-gateway.yaml
# Applying the Gateway (gatewayClassName: kgateway) auto-creates a Deployment +
# Service named after the Gateway ("kgw") in the default namespace; that Service
# is type LoadBalancer, so cloud-provider-kind hands it its own external IP.
# Provisioning is async — wait for the Deployment to appear, then for its rollout.
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  "${KUBECTL[@]}" -n default get deployment/kgw >/dev/null 2>&1 && break
  sleep "${POLL_INTERVAL:-2}"
done
"${KUBECTL[@]}" -n default rollout status deployment/kgw --timeout="${TIMEOUT}"

echo "kgateway installed. Its gateway Service gets its own LoadBalancer IP:"
"${KUBECTL[@]}" -n default get svc kgw \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via kgateway, e.g.:"
echo "  IP=\$(kubectl -n default get svc kgw -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
