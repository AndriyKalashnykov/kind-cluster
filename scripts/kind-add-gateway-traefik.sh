#!/usr/bin/env bash
# Enable Traefik's Kubernetes Gateway API provider IN ADDITION to classic Ingress,
# and route the demo apps through a Gateway + HTTPRoutes. Traefik serves both the
# existing networking.k8s.io/v1 Ingress AND Gateway API from the same pod — no
# extra workload. Requires `make ingress-traefik` (or `make install-all`) first.
#
# The Gateway API demo uses *.gw.localdev.me hostnames so it doesn't collide with
# the classic Ingress (*.localdev.me) on Traefik's shared web entrypoint, while
# routing to the SAME backend Services.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# Shared Gateway API CRDs (idempotent).
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

# Reuse the chart version pinned in kind-add-traefik.sh — single source of truth,
# Renovate-tracked there (avoids a second pin for the same dep).
TRAEFIK_CHART_VERSION=$(awk -F= '/^TRAEFIK_CHART_VERSION=/{print $2; exit}' "$SCRIPT_DIR/kind-add-traefik.sh")
CHART_URL="https://traefik.github.io/charts/traefik/traefik-${TRAEFIK_CHART_VERSION}.tgz"

echo "=== Enabling Traefik Gateway API provider (chart v${TRAEFIK_CHART_VERSION}) ==="
# --reuse-values keeps the original hostPort/nodeSelector/tolerations from
# kind-add-traefik.sh; we only add the Gateway API provider + a GatewayClass.
# gateway.enabled=false: we manage our own Gateway resource (k8s/gateway/) rather
# than the chart's default, so the listener/hostnames are explicit and reviewable.
# updateStrategy.type=Recreate is REQUIRED for this upgrade: Traefik binds
# hostPort 80/443, and the default RollingUpdate (maxSurge=1) would create a
# second pod that can never bind those ports while the old pod holds them →
# the rollout deadlocks ("context deadline exceeded"). Recreate tears the old
# pod down first (a brief restart), so the new pod with the Gateway provider
# can bind the host ports. (The base install also sets this now.)
helm --kube-context="kind-${KIND_CLUSTER_NAME}" upgrade traefik "$CHART_URL" \
    --namespace traefik --reuse-values \
    --set 'updateStrategy.type=Recreate' \
    --set 'providers.kubernetesGateway.enabled=true' \
    --set 'gatewayClass.enabled=true' \
    --set 'gateway.enabled=false' \
    --wait --timeout "${TIMEOUT}"

"${KUBECTL[@]}" -n traefik rollout status deployment/traefik --timeout="${TIMEOUT}"

echo "=== Applying demo Gateway + HTTPRoutes (*.gw.localdev.me) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/traefik-gateway.yaml
"${KUBECTL[@]}" wait --for=condition=Programmed gateway/traefik-gateway -n default --timeout="${TIMEOUT}" || true

echo "Traefik Gateway API enabled. Demo apps now also reachable via Gateway API, e.g.:"
echo "  curl -H 'Host: helloweb.gw.localdev.me' http://localhost/"
