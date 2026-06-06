#!/usr/bin/env bash
# Install the Kubernetes Gateway API CRDs (standard channel). Idempotent and
# version-pinned — both kind-add-gateway-traefik.sh and kind-add-gateway-istio.sh
# depend on these, and the CRDs are install-if-absent so running it twice is safe.
#
# Standard channel = GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant,
# BackendTLSPolicy. For TCPRoute/TLSRoute/UDPRoute use the experimental channel
# (not needed for the demo HTTP routes).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
GATEWAY_API_VERSION=v1.5.1

echo "=== Installing Gateway API CRDs (standard channel) ${GATEWAY_API_VERSION} ==="
"${KUBECTL[@]}" apply -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
"${KUBECTL[@]}" wait --for=condition=Established \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/gatewayclasses.gateway.networking.k8s.io \
  --timeout=60s
echo "Gateway API CRDs ready."
