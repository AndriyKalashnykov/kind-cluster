#!/usr/bin/env bash
# Install Kong (via the Kong Ingress Controller, KIC) as a Gateway API controller
# that coexists with Traefik, Istio, NGINX Gateway Fabric, Contour, Envoy Gateway
# and kgateway, fronting the SAME demo apps via its own LoadBalancer IP. Kong is
# NOT a CNI — it installs over the existing kindnet cluster.
#
# Unlike the per-Gateway-provisioning controllers (Istio/NGF/Contour/Envoy/kgw),
# KIC uses the UNMANAGED Gateway model: the data plane is the single
# `kong-gateway-proxy` LoadBalancer Service the chart already creates, and the
# GatewayClass is bound to it via the konghq.com/gatewayclass-unmanaged annotation.
# So Kong's "own LB IP" is that one proxy Service IP (shared by its Gateway API
# listeners AND its classic Ingress — KIC serves both from one install).
#
# KIC v3.x vendors sigs.k8s.io/gateway-api v1.3.0 — past the v1.2.0 floor where
# GatewayClass.status.supportedFeatures became an object-list — so it deserializes
# the cluster's v1.5.1 form natively (immune to the HAProxy crash). The umbrella
# `kong/ingress` chart runs DB-less by default (no Postgres). See
# docs/gateway-api-ingress.md.
#
# Requires `make install-all` first (cloud-provider-kind must be running so the
# kong-gateway-proxy Service gets an external IP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# renovate: datasource=helm depName=ingress registryUrl=https://charts.konghq.com
KONG_VERSION=0.24.0
KONG_CHARTS="https://charts.konghq.com"

# Shared Gateway API CRDs first (idempotent). KIC consumes whatever Gateway API
# CRDs exist (it does not bundle them), so the shared experimental-channel v1.5.1
# install satisfies it.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing Kong Ingress Controller ${KONG_VERSION} (umbrella chart, DB-less) ==="
"${HELM[@]}" repo add kong "$KONG_CHARTS" >/dev/null 2>&1 || true
"${HELM[@]}" repo update kong >/dev/null 2>&1 || true
# --wait blocks until the controller + gateway Deployments are Ready. The proxy
# Service is type LoadBalancer by default, so cloud-provider-kind assigns it an IP.
"${HELM[@]}" upgrade --install kong kong/ingress \
    --version "${KONG_VERSION}" --namespace kong --create-namespace \
    --wait --timeout "${TIMEOUT}"

echo "=== Applying Kong GatewayClass (unmanaged) + Gateway + HTTPRoutes ==="
"${KUBECTL[@]}" apply -f k8s/gateway/kong-gateway.yaml

# Discover the Kong proxy LoadBalancer Service by type (its name has varied across
# chart versions — kong-gateway-proxy / kong-proxy — so select the LB-typed Service
# in the kong namespace rather than hardcoding a name).
KONG_SVC=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  KONG_SVC=$("${KUBECTL[@]}" -n kong get svc \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "")
  [ -n "$KONG_SVC" ] && break
  sleep "${POLL_INTERVAL:-2}"
done

echo "Kong installed. Its proxy Service ($KONG_SVC) gets its own LoadBalancer IP:"
[ -n "$KONG_SVC" ] && "${KUBECTL[@]}" -n kong get svc "$KONG_SVC" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via Kong (Gateway API), e.g.:"
echo "  SVC=\$(kubectl -n kong get svc -o jsonpath='{range .items[?(@.spec.type==\"LoadBalancer\")]}{.metadata.name}{end}')"
echo "  IP=\$(kubectl -n kong get svc \$SVC -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
echo "Kong also serves classic Ingress on the same IP via 'ingressClassName: kong'."
