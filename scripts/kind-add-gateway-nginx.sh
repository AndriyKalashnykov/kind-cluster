#!/usr/bin/env bash
# Install NGINX Gateway Fabric (NGF, OSS) as a Gateway API controller that
# coexists with Traefik and Istio and fronts the SAME demo apps via its own
# LoadBalancer IP. NGF is NOT a CNI — it installs over the existing kindnet
# cluster. Like Istio, NGF provisions the data plane PER-GATEWAY: applying a
# Gateway with gatewayClassName: nginx auto-creates an nginx Deployment+Service
# named "<gateway>-nginx" in the Gateway's namespace.
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

# renovate: datasource=docker depName=ghcr.io/nginx/charts/nginx-gateway-fabric
NGF_VERSION=2.6.6
NGF_CHART="oci://ghcr.io/nginx/charts/nginx-gateway-fabric"

# Shared Gateway API CRDs first (idempotent). NGF 2.6.3 targets Gateway API
# v1.5.1 — the exact version this repo installs — so the shared experimental-
# channel CRDs satisfy it (NGF uses only the v1 GA resources, identical across
# channels); do NOT install NGF's own bundled copy (avoids CRD ownership
# conflicts with Traefik/Istio that share the same CRDs).
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing NGINX Gateway Fabric ${NGF_VERSION} (OSS, control plane) ==="
# helm --wait blocks until the control-plane Deployment is Ready. The chart
# default nginx.service.type=LoadBalancer applies to the per-Gateway data-plane
# Service provisioned below, so cloud-provider-kind assigns it an external IP.
"${HELM[@]}" upgrade --install ngf "$NGF_CHART" \
    --version "${NGF_VERSION}" --namespace nginx-gateway --create-namespace \
    --wait --timeout "${TIMEOUT}"

echo "=== Applying NGF Gateway + HTTPRoutes (auto-provisions an nginx data plane) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/nginx-gateway.yaml
# Applying the Gateway (gatewayClassName: nginx) auto-creates a Deployment +
# Service named "<gateway>-nginx" = "ngf-nginx" in the default namespace.
# Provisioning is async — wait for the Deployment to appear, then for its
# rollout (rollout status errors immediately if the object does not yet exist).
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  "${KUBECTL[@]}" -n default get deployment/ngf-nginx >/dev/null 2>&1 && break
  sleep "${POLL_INTERVAL:-2}"
done
"${KUBECTL[@]}" -n default rollout status deployment/ngf-nginx --timeout="${TIMEOUT}"

echo "NGINX Gateway Fabric installed. Its gateway Service gets its own LoadBalancer IP:"
"${KUBECTL[@]}" -n default get svc ngf-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via NGF, e.g.:"
echo "  IP=\$(kubectl -n default get svc ngf-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
