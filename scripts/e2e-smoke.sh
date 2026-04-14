#!/usr/bin/env bash
# Smoke-test deployed demo services. Assumes install-all has already been run
# (KinD cluster, ingress-nginx, MetalLB, demo apps).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KIND_NODE="${KIND_NODE:-kind-control-plane}"

INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
HELLOWEB_IP=$(kubectl get svc helloweb -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
GOLANG_IP=$(kubectl get svc golang-hello-world-web-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
FOO_IP=$(kubectl get svc foo-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

PASS=0
FAIL=0

pass() { echo "  ✓ PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ FAIL: $1"; FAIL=$((FAIL + 1)); }

check_curl() {
  local desc="$1" url="$2" expected="$3"
  shift 3
  local body
  if ! body=$(docker exec "$KIND_NODE" curl -sf --max-time 10 "$@" "$url" 2>&1); then
    fail "$desc — curl failed against $url"
    return
  fi
  if echo "$body" | grep -qF "$expected"; then
    pass "$desc — body contains '$expected'"
  else
    fail "$desc — body missing '$expected'. Got: $(echo "$body" | head -c 120)"
  fi
}

check_status() {
  local desc="$1" url="$2"
  shift 2
  if docker exec "$KIND_NODE" curl -sf --max-time 10 "$@" "$url" >/dev/null; then
    pass "$desc — HTTP 2xx"
  else
    fail "$desc — non-2xx from $url"
  fi
}

check_status_code() {
  local desc="$1" url="$2" expected="$3"
  shift 3
  local code
  code=$(docker exec "$KIND_NODE" curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" "$url" 2>/dev/null || echo "000")
  if [ "$code" = "$expected" ]; then
    pass "$desc — HTTP $code"
  else
    fail "$desc — got HTTP $code, expected $expected"
  fi
}

echo "=== E2E smoke tests ==="

# --- Demo workload assertions (body-asserting) ---
check_curl   "demo.localdev.me ingress" "http://${INGRESS_IP}/" "It works!" -H "Host: demo.localdev.me"
check_curl   "helloweb"                 "http://${HELLOWEB_IP}/" "Hello, world!"
check_status "golang /healthz"          "http://${GOLANG_IP}:8080/healthz"
check_status "golang /myhello/"         "http://${GOLANG_IP}:8080/myhello/"
# foo-service load-balances across foo-app and bar-app deployments (shared selector
# `app: http-echo`); accept either body.
if body=$(docker exec "$KIND_NODE" curl -sf --max-time 10 "http://${FOO_IP}:5678/" 2>/dev/null) \
    && [[ "$body" =~ ^(foo|bar)$ ]]; then
  pass "foo-service — body matches foo|bar (got '$body')"
else
  fail "foo-service — unexpected body: $(echo "${body:-<none>}" | head -c 120)"
fi

# --- Negative case: unknown Host on ingress should NOT match the demo route ---
check_status_code "ingress unknown Host returns 404" "http://${INGRESS_IP}/" 404 -H "Host: nonexistent.example"

# --- Cert export: kind-export-cert.sh produces these in repo root ---
if [ -f "$REPO_ROOT/cluster-ca.crt" ]; then
  if openssl x509 -in "$REPO_ROOT/cluster-ca.crt" -noout -subject >/dev/null 2>&1; then
    pass "cluster-ca.crt is a valid X.509 certificate"
  else
    fail "cluster-ca.crt is not a valid X.509 certificate"
  fi
else
  fail "cluster-ca.crt missing — kind-export-cert.sh did not run"
fi
if [ -s "$REPO_ROOT/client.pfx" ]; then
  pass "client.pfx exists and is non-empty"
else
  fail "client.pfx missing or empty"
fi

# --- Dashboard token: kind-add-dashboard.sh writes to repo root ---
if [ -s "$REPO_ROOT/dashboard-admin-token.txt" ]; then
  TOKEN=$(tr -d '[:space:]' < "$REPO_ROOT/dashboard-admin-token.txt")
  # JWT = three base64url segments separated by dots
  if [[ "$TOKEN" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
    pass "dashboard-admin-token.txt is a well-formed JWT"
  else
    fail "dashboard-admin-token.txt is not a JWT (got ${#TOKEN} chars)"
  fi
else
  fail "dashboard-admin-token.txt missing or empty"
fi

# --- Metrics-server API: APIService should be Available and serve nodes ---
if kubectl get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q '^True$'; then
  pass "metrics.k8s.io APIService is Available"
else
  fail "metrics.k8s.io APIService is not Available"
fi
# kubectl top nodes can take ~30s after install before metrics are populated
if for _ in $(seq 1 12); do
     out=$(kubectl top nodes 2>/dev/null) && [ "$(echo "$out" | wc -l)" -ge 2 ] && break
     sleep 5
   done && [ "$(echo "$out" | wc -l)" -ge 2 ]; then
  pass "kubectl top nodes returns >=1 row"
else
  fail "kubectl top nodes returned no rows after 60s"
fi

# --- NFS CSI provisioner: PVC should bind ---
kubectl apply -f "$REPO_ROOT/k8s/nfs/pvc-incluster.yaml" >/dev/null
if kubectl wait pvc/demo-claim-incluster --for=jsonpath='{.status.phase}'=Bound --timeout=120s >/dev/null 2>&1; then
  pass "NFS PVC demo-claim-incluster bound"
else
  fail "NFS PVC demo-claim-incluster did not bind within 120s"
fi
kubectl delete pvc demo-claim-incluster --ignore-not-found --wait=false >/dev/null 2>&1 || true

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
