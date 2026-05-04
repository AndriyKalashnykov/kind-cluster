#!/usr/bin/env bash
# Smoke-test scripts/migrate-from-metallb.sh on a running MetalLB cluster.
# Pre-conditions (caller's responsibility):
#   - KinD cluster running
#   - ingress-nginx + MetalLB installed
#   - demo workloads deployed and serving (i.e. `LB=metallb make install-all`
#     or the equivalent CI sequence has just succeeded)
#
# Asserts the MetalLB → cloud-provider-kind migration:
#   1. metallb-system namespace existed pre-migration
#   2. migrate-from-metallb.sh runs cleanly
#   3. cloud-provider-kind container is Up post-migration
#   4. metallb-system namespace is gone post-migration
#   5. ingress-nginx Service gets a fresh LoadBalancer IP from CPK
#   6. demo.localdev.me responds with the expected body through the new IP
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

PASS=0
FAIL=0
pass() { echo "  ✓ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Migration smoke test (MetalLB → cloud-provider-kind) ==="

# --- Pre-conditions ---
if kubectl get ns metallb-system >/dev/null 2>&1; then
  pass "metallb-system namespace present pre-migration"
else
  fail "metallb-system namespace missing — caller must run 'LB=metallb make install-all' first"
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

INITIAL_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
if [ -n "$INITIAL_IP" ]; then
  pass "ingress-nginx had MetalLB-assigned IP pre-migration ($INITIAL_IP)"
else
  fail "ingress-nginx had no MetalLB-assigned IP pre-migration"
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
for _ in $(seq 1 30); do
  kubectl get ns metallb-system >/dev/null 2>&1 || break
  sleep 2
done
if kubectl get ns metallb-system >/dev/null 2>&1; then
  fail "metallb-system namespace still exists 60s after migration"
else
  pass "metallb-system namespace removed"
fi

# CPK re-allocates LB IPs after the kick. Wait for ingress to get a fresh one.
NEW_IP=""
for _ in $(seq 1 60); do
  NEW_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [ -n "$NEW_IP" ] && break
  sleep 2
done
if [ -n "$NEW_IP" ]; then
  pass "ingress-nginx reassigned a LoadBalancer IP under CPK ($NEW_IP)"
else
  fail "ingress-nginx did not get a LoadBalancer IP from CPK within 120s"
  kubectl get svc -n ingress-nginx ingress-nginx-controller -o yaml || true
  echo "=== Results: $PASS passed, $FAIL failed ==="
  exit 1
fi

# K1.5 — IP assigned ≠ IP routable. Poll the body until ready.
ROUTED=0
for i in $(seq 1 60); do
  if docker exec kind-control-plane curl -sf --max-time 3 -H 'Host: demo.localdev.me' "http://${NEW_IP}/" 2>/dev/null | grep -q 'It works!'; then
    pass "demo.localdev.me reachable through CPK after $((i * 2))s"
    ROUTED=1
    break
  fi
  sleep 2
done
if [ "$ROUTED" -ne 1 ]; then
  fail "demo.localdev.me did not respond through CPK within 120s"
  kubectl -n ingress-nginx get pods -o wide || true
  docker ps --filter name=cloud-provider-kind --filter name=kindccm- --format 'table {{.Names}}\t{{.Status}}' || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
