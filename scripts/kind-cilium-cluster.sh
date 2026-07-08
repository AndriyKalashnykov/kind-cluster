#!/usr/bin/env bash
# Create a DEDICATED KinD cluster running Cilium as the CNI, with Cilium's
# Gateway API controller, and route a demo app through a Gateway + HTTPRoute
# reachable from the host on a Cilium Node-IPAM LoadBalancer IP.
#
# Why a separate cluster: Cilium Gateway API requires kube-proxy replacement
# (kubeProxyReplacement=true) and disableDefaultCNI — both cluster-CREATION-time
# settings, mutually exclusive with the lab's kindnet + kube-proxy install-all
# cluster. So Cilium can never be an add-on; it gets its own cluster.
#
# Verified end-to-end on KinD 2026-07-08 (see docs/gateway-api-ingress.md
# "Cilium Gateway API on KinD"). Key design points, each load-bearing:
#   * Gateway API CRDs are pinned to Cilium 1.19's OWN supported version
#     (v1.4.1), NOT the lab's shared experimental v1.6.0 — a newer CRD set
#     triggers the GatewayClass.status.supportedFeatures []string->[]object
#     skew that dropped HAProxy.
#   * LB IP via Cilium Node IPAM (io.cilium/node): the Gateway Service gets a
#     node IP, already host-routable on the kind docker subnet, with NO L2
#     announcements — sidestepping cilium/cilium#46260 (the endpoint-less L7LB
#     TPROXY drop that only affects non-bridge L2-announced devices).
#   * Node IPAM is attached to the Gateway via a GatewayClass-level
#     parametersRef -> CiliumGatewayClassConfig (the per-Gateway
#     infrastructure.parametersRef is NOT honoured by Cilium 1.19).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

# Dedicated cluster name (distinct from install-all's default `kind`, so both
# can coexist on one host). Context is kind-${CILIUM_CLUSTER_NAME}.
CILIUM_CLUSTER_NAME="${CILIUM_CLUSTER_NAME:-cilium}"
KUBECTL=(kubectl --context="kind-${CILIUM_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${CILIUM_CLUSTER_NAME}")

# renovate: datasource=helm depName=cilium registryUrl=https://helm.cilium.io/
CILIUM_VERSION=1.19.5
# Gateway API CRD channel Cilium 1.19 is TESTED against (v1.4.1). Do NOT bump to
# the lab's shared v1.6.0 pin, and do NOT Renovate-track this to latest — it is
# COUPLED to CILIUM_VERSION (a newer CRD set than Cilium vendors re-introduces
# the supportedFeatures skew). Re-check against the Cilium Gateway API docs on
# every CILIUM_VERSION bump.
CILIUM_GATEWAY_API_VERSION=v1.4.1

READY_TIMEOUT="${READY_TIMEOUT:-180s}"

if kind get clusters 2>/dev/null | grep -qx "${CILIUM_CLUSTER_NAME}"; then
    echo "Cilium cluster '${CILIUM_CLUSTER_NAME}' already exists — reusing it."
    kubectl config use-context "kind-${CILIUM_CLUSTER_NAME}" >/dev/null
else
    # Ingress-free cluster: the Gateway data plane is reached via its LB IP, so
    # no host-port preflight is needed beyond what kind itself binds.
    echo "==> Creating dedicated Cilium cluster '${CILIUM_CLUSTER_NAME}' (no CNI, no kube-proxy)"
    KIND_ARGS=(--config=./k8s/cilium/kind-config-cilium.yaml --name "${CILIUM_CLUSTER_NAME}" --wait 0s)
    if [ -n "${KIND_NODE_IMAGE:-}" ]; then
        KIND_ARGS+=(--image="$KIND_NODE_IMAGE")
    fi
    kind create cluster "${KIND_ARGS[@]}"
fi

echo "==> Installing Gateway API ${CILIUM_GATEWAY_API_VERSION} CRDs (Cilium's supported version)"
"${KUBECTL[@]}" apply --server-side --force-conflicts \
    -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${CILIUM_GATEWAY_API_VERSION}/experimental-install.yaml" >/dev/null

echo "==> Installing Cilium ${CILIUM_VERSION} (kube-proxy-free, Gateway API, Node IPAM)"
helm repo add cilium https://helm.cilium.io/ >/dev/null 2>&1 || true
helm repo update cilium >/dev/null 2>&1 || true
"${HELM[@]}" upgrade --install cilium cilium/cilium --version "${CILIUM_VERSION}" \
    --namespace kube-system \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost="${CILIUM_CLUSTER_NAME}-control-plane" \
    --set k8sServicePort=6443 \
    --set gatewayAPI.enabled=true \
    --set l7Proxy=true \
    --set nodeIPAM.enabled=true \
    --set ipam.mode=kubernetes \
    --set image.pullPolicy=IfNotPresent \
    --set operator.replicas=1 >/dev/null

echo "==> Waiting for nodes Ready (Cilium is the CNI now)"
"${KUBECTL[@]}" wait --for=condition=Ready nodes --all --timeout="${READY_TIMEOUT}" >/dev/null

echo "==> Wiring Node IPAM onto the cilium GatewayClass (parametersRef -> CiliumGatewayClassConfig)"
"${KUBECTL[@]}" apply -f k8s/cilium/cilium-gateway.yaml >/dev/null 2>&1 || true
# The GatewayClass is Cilium-managed; patch its parametersRef so the Gateway's
# LoadBalancer Service is created with loadBalancerClass io.cilium/node.
"${KUBECTL[@]}" patch gatewayclass cilium --type=merge \
    -p '{"spec":{"parametersRef":{"group":"cilium.io","kind":"CiliumGatewayClassConfig","name":"node-ipam","namespace":"default"}}}' >/dev/null
# Recreate the Gateway so its Service is (re)created with the class now in effect
# (loadBalancerClass is immutable, so a Gateway created before the patch keeps a
# class-less, unroutable Service).
"${KUBECTL[@]}" delete gateway cilium-gw --ignore-not-found --wait=true >/dev/null 2>&1 || true

echo "==> Deploying demo app + Cilium Gateway + HTTPRoute"
"${KUBECTL[@]}" apply -f k8s/helloweb-deployment.yaml >/dev/null
"${KUBECTL[@]}" apply -f k8s/cilium/cilium-gateway.yaml >/dev/null
"${KUBECTL[@]}" rollout status deployment/helloweb --timeout="${READY_TIMEOUT}" >/dev/null

echo "==> Waiting for the Gateway's Node-IPAM LoadBalancer IP"
CILIUM_LB_IP=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
    CILIUM_LB_IP=$("${KUBECTL[@]}" get svc cilium-gateway-cilium-gw \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$CILIUM_LB_IP" ] && break
    sleep "${POLL_INTERVAL:-2}"
done
if [ -z "$CILIUM_LB_IP" ]; then
    echo "ERROR: Cilium Gateway Service did not get a Node-IPAM LoadBalancer IP" >&2
    "${KUBECTL[@]}" get gateway cilium-gw -o wide >&2 || true
    exit 1
fi

echo "==> Verifying host reachability of the Gateway LB IP (K1.5 route-readiness poll)"
OK=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
    if curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${CILIUM_LB_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        OK=yes; break
    fi
    sleep "${POLL_INTERVAL:-2}"
done

echo
if [ -n "$OK" ]; then
    echo "SUCCESS: Cilium Gateway API is serving on http://${CILIUM_LB_IP}/ (Host: helloweb.localdev.me)"
    echo "  curl -H 'Host: helloweb.localdev.me' http://${CILIUM_LB_IP}/"
    echo "  Tear down: make cilium-cluster-destroy   (or: kind delete cluster --name ${CILIUM_CLUSTER_NAME})"
else
    echo "ERROR: Cilium Gateway LB IP ${CILIUM_LB_IP} did not route to helloweb within the poll window" >&2
    "${KUBECTL[@]}" get gateway,httproute,svc -A 2>&1 | grep -iE 'cilium|helloweb' >&2 || true
    exit 1
fi
