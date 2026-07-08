#!/usr/bin/env bash
# Smoke-test scripts/migrate-from-metallb.sh on a running MetalLB cluster.
# Pre-conditions (caller's responsibility):
#   - KinD cluster running
#   - Traefik + MetalLB installed
#   - demo workloads deployed and serving (i.e. `LB=metallb make install-all`
#     or the equivalent CI sequence has just succeeded)
#
# Asserts the MetalLB → cloud-provider-kind migration:
#   1. metallb-system namespace existed pre-migration
#   2. migrate-from-metallb.sh runs cleanly
#   3. cloud-provider-kind container is Up post-migration
#   4. metallb-system namespace is gone post-migration
#   5. Traefik Service gets a fresh LoadBalancer IP from CPK
#   6. demo.localdev.me responds with the expected body through the new IP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

# KinD names the control-plane node "<cluster>-control-plane"; derive it from
# KIND_CLUSTER_NAME so an overridden cluster name still resolves the right
# container for `docker exec` (mirrors e2e-smoke.sh).
KIND_NODE="${KIND_NODE:-$(kube_node_name "$KIND_CLUSTER_NAME")}"

PASS=0
FAIL=0
pass() { echo "  ✓ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Migration smoke test (MetalLB → cloud-provider-kind) ==="

# --- Pre-conditions ---
if "${KUBECTL[@]}" get ns metallb-system >/dev/null 2>&1; then
  pass "metallb-system namespace present pre-migration"
else
  fail "metallb-system namespace missing — caller must run 'LB=metallb make install-all' first"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

INITIAL_IP=$("${KUBECTL[@]}" get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$INITIAL_IP" ]; then
  pass "Traefik had MetalLB-assigned IP pre-migration ($INITIAL_IP)"
else
  fail "Traefik had no MetalLB-assigned IP pre-migration"
fi

# --- Run migration ---
echo ""
echo "--- Running migrate-from-metallb.sh ---"
./scripts/migrate-from-metallb.sh
echo ""

# --- Post-conditions ---
if docker ps --filter name=cloud-provider-kind --format '{{.Names}}' | grep -qx cloud-provider-kind; then
  pass "cloud-provider-kind container is Up"
else
  fail "cloud-provider-kind container did not start"
fi

# Allow the ns up to 60s to finish Terminating (CRD finalizers can be slow)
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  "${KUBECTL[@]}" get ns metallb-system >/dev/null 2>&1 || break
  sleep "${POLL_INTERVAL:-2}"
done
if "${KUBECTL[@]}" get ns metallb-system >/dev/null 2>&1; then
  fail "metallb-system namespace still exists 60s after migration"
else
  pass "metallb-system namespace removed"
fi

# CPK re-allocates LB IPs after the kick. Wait for ingress to get a fresh one.
NEW_IP=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-60}"); do
  NEW_IP=$("${KUBECTL[@]}" get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [ -n "$NEW_IP" ] && break
  sleep "${POLL_INTERVAL:-2}"
done
if [ -n "$NEW_IP" ]; then
  pass "Traefik reassigned a LoadBalancer IP under CPK ($NEW_IP)"
else
  fail "Traefik did not get a LoadBalancer IP from CPK within 120s"
  "${KUBECTL[@]}" get svc -n traefik traefik -o yaml || true
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# K1.5 — IP assigned ≠ IP routable. Poll the body until ready.
ROUTED=0
for i in $(seq 1 "${POLL_ATTEMPTS:-60}"); do
  if docker exec "$KIND_NODE" curl -sf --max-time 3 -H 'Host: demo.localdev.me' "http://${NEW_IP}/" 2>/dev/null | grep -q 'It works!'; then
    pass "demo.localdev.me reachable through CPK after $((i * ${POLL_INTERVAL:-2}))s"
    ROUTED=1
    break
  fi
  sleep "${POLL_INTERVAL:-2}"
done
if [ "$ROUTED" -ne 1 ]; then
  fail "demo.localdev.me did not respond through CPK within 120s"
  "${KUBECTL[@]}" -n traefik get pods -o wide || true
  docker ps --filter name=cloud-provider-kind --filter name=kindccm- --format 'table {{.Names}}\t{{.Status}}' || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
