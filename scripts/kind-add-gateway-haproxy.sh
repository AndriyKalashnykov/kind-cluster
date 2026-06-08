#!/usr/bin/env bash
# Install HAProxy Ingress (jcmoraisjr/haproxy-ingress, OSS — the project on the
# official Gateway API implementations list) as a Gateway API controller that
# coexists with Traefik, Istio, NGINX Gateway Fabric and Contour, fronting the
# SAME demo apps via its own LoadBalancer IP. NOT a CNI.
#
# Unlike Istio/NGF/Contour (per-Gateway data planes), HAProxy Ingress uses ONE
# shared proxy behind a single LoadBalancer Service (the controller release),
# serving every Gateway/HTTPRoute for GatewayClass `haproxy`.
#
# NOTE: stable v0.16.1 does NOT update Gateway/HTTPRoute `.status` (status
# reporting landed after 0.16). So readiness/coexistence is verified by the
# controller Service's LB IP + an actual HTTP request, not by an `Accepted`
# GatewayClass condition (see scripts/e2e-smoke.sh).
#
# Requires `make install-all` first (cloud-provider-kind for the LB IP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# renovate: datasource=helm depName=haproxy-ingress registryUrl=https://haproxy-ingress.github.io/charts
HAPROXY_INGRESS_CHART_VERSION=0.16.1
HAPROXY_CHARTS="https://haproxy-ingress.github.io/charts"

# Shared Gateway API CRDs first (idempotent). The controller enables its Gateway
# API watcher (--watch-gateway, on by default) only when the CRDs are present;
# the shared standard-channel v1.5.1 CRDs satisfy GatewayClass/Gateway/HTTPRoute.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing HAProxy Ingress chart ${HAPROXY_INGRESS_CHART_VERSION} (OSS) ==="
helm repo add haproxy-ingress "$HAPROXY_CHARTS" >/dev/null 2>&1 || true
helm repo update haproxy-ingress >/dev/null
# controller.service.type=LoadBalancer (chart default, set explicitly) -> a
# cloud-provider-kind IP. A non-empty ingressClass is REQUIRED when the Gateway
# API watcher is on (the controller errors at startup otherwise). helm --wait
# blocks until the controller Deployment is Ready.
"${HELM[@]}" upgrade --install haproxy-ingress haproxy-ingress/haproxy-ingress \
    --version "${HAPROXY_INGRESS_CHART_VERSION}" \
    --namespace haproxy-ingress --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.ingressClass=haproxy \
    --wait --timeout "${TIMEOUT}"

echo "=== Applying HAProxy GatewayClass + Gateway + HTTPRoutes ==="
# v0.16.1's chart does not ship a GatewayClass (that landed in 0.17-alpha), so we
# create it; controllerName is hardcoded in the controller and cannot change.
"${KUBECTL[@]}" apply -f k8s/gateway/haproxy-gateway.yaml

echo "HAProxy Ingress installed. Its controller Service gets its own LoadBalancer IP:"
"${KUBECTL[@]}" -n haproxy-ingress get svc haproxy-ingress \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via HAProxy, e.g.:"
echo "  IP=\$(kubectl -n haproxy-ingress get svc haproxy-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
