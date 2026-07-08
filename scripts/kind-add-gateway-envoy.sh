#!/usr/bin/env bash
# Install Envoy Gateway as a Gateway API controller that coexists with Traefik,
# Istio, NGINX Gateway Fabric and Contour and fronts the SAME demo apps via its
# own LoadBalancer IP. Envoy Gateway is NOT a CNI — it installs over the existing
# kindnet cluster. Applying a Gateway with gatewayClassName: envoy auto-provisions
# an Envoy data-plane Deployment+Service in the envoy-gateway-system namespace,
# named "envoy-<gw-namespace>-<gw-name>-<hash>" (so it must be discovered by
# label, not a fixed name — unlike ngf-nginx / envoy-contour).
#
# Envoy Gateway v1.8.x vendors sigs.k8s.io/gateway-api v1.5.1 — the EXACT version
# this repo installs — so it deserializes the v1.5.1 GatewayClass.status
# .supportedFeatures object-list natively and cannot hit the crash that dropped
# HAProxy Ingress (which vendored a pre-v1.2.0 []string form). See
# docs/gateway-api-ingress.md.
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

# renovate: datasource=docker depName=docker.io/envoyproxy/gateway-helm
ENVOY_GATEWAY_VERSION=1.8.2
ENVOY_GATEWAY_CHART="oci://docker.io/envoyproxy/gateway-helm"
ENVOY_GATEWAY_CRDS_CHART="oci://docker.io/envoyproxy/gateway-crds-helm"

# Shared Gateway API CRDs first (idempotent). Envoy Gateway v1.8.1 vendors
# Gateway API v1.5.1 exactly, so the shared experimental-channel CRDs satisfy it.
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing Envoy Gateway ${ENVOY_GATEWAY_VERSION} (control plane) ==="
# Install ONLY Envoy Gateway's OWN CRDs (gateway.envoyproxy.io/*); reuse the
# cluster's shared Gateway API CRDs (crds.gatewayAPI.enabled=false) so we do not
# clobber the install Traefik/Istio/NGF/Contour share. --server-side avoids the
# 256 KiB last-applied-configuration annotation limit on large CRDs.
"${HELM[@]}" template eg-crds "$ENVOY_GATEWAY_CRDS_CHART" \
    --version "${ENVOY_GATEWAY_VERSION}" \
    --set crds.gatewayAPI.enabled=false \
    --set crds.envoyGateway.enabled=true \
  | "${KUBECTL[@]}" apply --server-side --force-conflicts -f -

# Main chart without the bundled Gateway API CRDs (--skip-crds) and without
# re-rendering the safe-upgrades ValidatingAdmissionPolicy the shared
# experimental bundle already provides.
"${HELM[@]}" upgrade --install eg "$ENVOY_GATEWAY_CHART" \
    --version "${ENVOY_GATEWAY_VERSION}" --namespace envoy-gateway-system --create-namespace \
    --skip-crds \
    --set crds.gatewayAPI.safeUpgradePolicy.enabled=false \
    --wait --timeout "${TIMEOUT}"
"${KUBECTL[@]}" -n envoy-gateway-system rollout status deployment/envoy-gateway --timeout="${TIMEOUT}"

echo "=== Applying Envoy Gateway + HTTPRoutes (auto-provisions an Envoy data plane) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/envoy-gateway.yaml
# Applying the Gateway (gatewayClassName: envoy) auto-creates a Deployment +
# Service in envoy-gateway-system with a generated name; discover it by the
# owning-gateway labels. Provisioning is async — wait for the Service to appear.
ENVOY_SVC=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  ENVOY_SVC=$("${KUBECTL[@]}" -n envoy-gateway-system get svc \
    -l gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=eg \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [ -n "$ENVOY_SVC" ] && break
  sleep "${POLL_INTERVAL:-2}"
done
[ -n "$ENVOY_SVC" ] && "${KUBECTL[@]}" -n envoy-gateway-system rollout status "deployment/${ENVOY_SVC}" --timeout="${TIMEOUT}" || true

echo "Envoy Gateway installed. Its gateway Service gets its own LoadBalancer IP:"
[ -n "$ENVOY_SVC" ] && "${KUBECTL[@]}" -n envoy-gateway-system get svc "$ENVOY_SVC" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via Envoy Gateway, e.g.:"
echo "  SVC=\$(kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=eg -o jsonpath='{.items[0].metadata.name}')"
echo "  IP=\$(kubectl -n envoy-gateway-system get svc \$SVC -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
