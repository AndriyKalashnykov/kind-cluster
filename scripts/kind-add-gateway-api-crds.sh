#!/usr/bin/env bash
# Install the Kubernetes Gateway API CRDs (experimental channel). Idempotent and
# version-pinned — every kind-add-gateway-*.sh installer depends on these, and the
# CRDs are install-if-absent so running it twice is safe.
#
# We install the EXPERIMENTAL channel, not standard. The experimental channel is a
# strict SUPERSET of standard: it ships the same v1 GA resources (GatewayClass,
# Gateway, HTTPRoute, GRPCRoute, ReferenceGrant, BackendTLSPolicy) PLUS the alpha
# ones (TCPRoute, TLSRoute@v1alpha2, UDPRoute). Project Contour's controller
# FATALLY requires `TLSRoute` at `gateway.networking.k8s.io/v1alpha2` to start
# (it creates a TLSRoute informer unconditionally) — that version is served only
# by the experimental channel. Traefik, Istio and NGINX Gateway Fabric all use
# only the v1 GA resources, which are identical across channels, so the superset
# satisfies every controller this repo wires.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

# renovate: datasource=github-releases depName=kubernetes-sigs/gateway-api
GATEWAY_API_VERSION=v1.6.1

echo "=== Installing Gateway API CRDs (experimental channel) ${GATEWAY_API_VERSION} ==="
# --server-side is REQUIRED here: the experimental HTTPRoute CRD schema exceeds
# the 256 KiB limit for the client-side `last-applied-configuration` annotation
# that a plain `kubectl apply` writes ("metadata.annotations: Too long"). Server-
# side apply stores no such annotation. --force-conflicts lets a re-run (or a
# different field manager) re-own fields idempotently.
"${KUBECTL[@]}" apply --server-side --force-conflicts -f \
  "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/experimental-install.yaml"
"${KUBECTL[@]}" wait --for=condition=Established \
  crd/gateways.gateway.networking.k8s.io \
  crd/httproutes.gateway.networking.k8s.io \
  crd/gatewayclasses.gateway.networking.k8s.io \
  --timeout=60s
echo "Gateway API CRDs ready."
