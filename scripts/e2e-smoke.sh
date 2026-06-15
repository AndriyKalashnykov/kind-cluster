#!/usr/bin/env bash
# Smoke-test deployed demo services. Assumes install-all has already been run
# (KinD cluster, Traefik, LoadBalancer provider, demo apps).
#
# All HTTP demo apps (httpd, helloweb, golang, foo) are reached through
# Traefik's LoadBalancer IP with a Host header — the LB provider
# (cloud-provider-kind or MetalLB) allocates exactly ONE IP for the ingress
# controller, which fronts every demo app by virtual-host routing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
# container for `docker exec`.
KIND_NODE="${KIND_NODE:-$(kube_node_name "$KIND_CLUSTER_NAME")}"

INGRESS_IP=$("${KUBECTL[@]}" get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

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

# --- Cluster infrastructure: readiness of ingress controller and MetalLB ---
if "${KUBECTL[@]}" -n traefik rollout status deploy/traefik --timeout=60s >/dev/null 2>&1; then
  pass "Traefik controller deployment is rolled out"
else
  fail "Traefik controller rollout did not complete within 60s"
fi

if [ -n "$("${KUBECTL[@]}" -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)" ]; then
  pass "Traefik service has a LoadBalancer ingress IP"
else
  fail "Traefik service has no .status.loadBalancer.ingress[0].ip — LB provider did not assign an IP"
fi

case "${LB:-cpk}" in
  cpk)
    if docker ps --filter name=cloud-provider-kind --format '{{.Status}}' | grep -q '^Up'; then
      pass "cloud-provider-kind container is Up"
    else
      fail "cloud-provider-kind container is not Up"
    fi
    ;;
  metallb)
    if "${KUBECTL[@]}" -n metallb-system get ipaddresspool -o name 2>/dev/null | grep -q .; then
      pass "MetalLB IPAddressPool exists"
    else
      fail "MetalLB IPAddressPool missing — LoadBalancer services cannot be assigned IPs"
    fi
    ;;
  *)
    fail "unknown LB provider '${LB}'"
    ;;
esac

# --- Demo workload assertions (body-asserting, all through ingress) ---
# K2 guard: every assertion checks body content distinctive to the real backend,
# NOT just status. Nginx-ingress's default backend answers `/healthz` with 200
# regardless of Host — a plain status check would pass even when the Host-to-
# service route is broken. Body strings used below only appear when the request
# actually reached the intended backend pod.
check_curl   "demo.localdev.me"       "http://${INGRESS_IP}/"           "It works!"      -H "Host: demo.localdev.me"
check_curl   "helloweb.localdev.me"   "http://${INGRESS_IP}/"           "Hello, world!"  -H "Host: helloweb.localdev.me"
check_curl   "golang.localdev.me /healthz"  "http://${INGRESS_IP}/healthz"  '"health":"ok"'  -H "Host: golang.localdev.me"
check_curl   "golang.localdev.me /myhello/" "http://${INGRESS_IP}/myhello/" "Hello, World"   -H "Host: golang.localdev.me"

# golang-web deployment-level readiness — the ingress curl above proves one path
# works, but a degraded rollout (e.g. a future replica with a misconfigured probe)
# would be masked by ingress load-balancing to the healthy pod. Assert the
# Deployment itself reports its replicas Ready.
if "${KUBECTL[@]}" rollout status deploy/golang-hello-world-web --timeout=60s >/dev/null 2>&1; then
  pass "golang-hello-world-web deployment is rolled out"
else
  fail "golang-hello-world-web rollout did not complete within 60s"
fi
GOLANG_READY=$("${KUBECTL[@]}" get deploy golang-hello-world-web -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [ "${GOLANG_READY:-0}" -ge 1 ]; then
  pass "golang-hello-world-web has >=1 ready replica (${GOLANG_READY})"
else
  fail "golang-hello-world-web has no ready replicas"
fi

# foo-service load-balances across foo-app and bar-app deployments (shared selector
# `app: http-echo`); accept either body.
if body=$(docker exec "$KIND_NODE" curl -sf --max-time 10 -H "Host: foo.localdev.me" "http://${INGRESS_IP}/" 2>/dev/null) \
    && [[ "$body" =~ ^(foo|bar)$ ]]; then
  pass "foo.localdev.me — body matches foo|bar (got '$body')"
else
  fail "foo.localdev.me — unexpected body: $(echo "${body:-<none>}" | head -c 120)"
fi

# foo-service must spread traffic across BOTH backends (foo-app -text=foo and
# bar-app -text=bar share selector app:http-echo). The single curl above only
# proves "a valid backend answered"; loop until both bodies are observed to
# prove the Service actually load-balances (a broken selector pinning all
# traffic to one deployment would pass the single check but fail here).
SAW_FOO=""; SAW_BAR=""
for _ in $(seq 1 20); do
  b=$(docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: foo.localdev.me" "http://${INGRESS_IP}/" 2>/dev/null || true)
  [ "$b" = "foo" ] && SAW_FOO=yes
  [ "$b" = "bar" ] && SAW_BAR=yes
  [ -n "$SAW_FOO" ] && [ -n "$SAW_BAR" ] && break
done
if [ -n "$SAW_FOO" ] && [ -n "$SAW_BAR" ]; then
  pass "foo-service load-balances across foo-app and bar-app (both bodies observed)"
else
  fail "foo-service did not exercise both backends in 20 requests (foo=${SAW_FOO:-no} bar=${SAW_BAR:-no})"
fi

# --- Negative case: unknown Host on ingress should NOT match the demo route ---
check_status_code "ingress unknown Host returns 404" "http://${INGRESS_IP}/" 404 -H "Host: nonexistent.example"

# --- Traefik websecure (HTTPS/443) entrypoint ---
# kind-add-traefik.sh sets ports.websecure.hostPort=443; Traefik serves TLS with a
# default self-signed cert (so -k). A demo Host routes to the same httpd backend as
# HTTP — the body marker proves the TLS handshake succeeded AND the route matched.
check_curl "demo.localdev.me over HTTPS (websecure/443)" "https://${INGRESS_IP}/" "It works!" -k -H "Host: demo.localdev.me"

# --- kind-config extraPortMappings: host :80 -> control-plane :80 -> Traefik ---
# k8s/kind-config.yaml maps containerPort 80 -> hostPort 80 on the control-plane
# node; Traefik's web entrypoint (ports.web.hostPort=80, pinned to control-plane via
# ingress-ready=true) binds it. This is a HOST-side curl (NOT docker exec) — it
# proves the host port mapping the kind config promises actually serves.
if body=$(curl -sf --max-time 10 -H "Host: demo.localdev.me" "http://localhost/" 2>/dev/null) \
    && echo "$body" | grep -qF "It works!"; then
  pass "host :80 -> control-plane :80 -> Traefik (curl http://localhost/ with demo Host)"
else
  fail "host :80 mapping not serving — curl http://localhost/ did not reach the httpd backend"
fi

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

# --- Headlamp token: kind-add-headlamp.sh writes to repo root ---
if [ -s "$REPO_ROOT/headlamp-admin-token.txt" ]; then
  TOKEN=$(tr -d '[:space:]' < "$REPO_ROOT/headlamp-admin-token.txt")
  # JWT = three base64url segments separated by dots
  if [[ "$TOKEN" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
    pass "headlamp-admin-token.txt is a well-formed JWT"
  else
    fail "headlamp-admin-token.txt is not a JWT (got ${#TOKEN} chars)"
  fi
else
  fail "headlamp-admin-token.txt missing or empty"
fi

# --- Headlamp UI reachability + admin RBAC (always-on: install-all installs it) ---
# Headlamp is a ClusterIP Service (headlamp/headlamp:80). Reach it via an ephemeral
# port-forward using the same pf_local_port idiom as scripts/test-registry.sh.
if "${KUBECTL[@]}" -n headlamp rollout status deploy/headlamp --timeout=60s >/dev/null 2>&1; then
  pass "Headlamp deployment is rolled out"
else
  fail "Headlamp deployment rollout did not complete within 60s"
fi

HL_PF_LOG=$(mktemp)
"${KUBECTL[@]}" -n headlamp port-forward svc/headlamp :80 >"$HL_PF_LOG" 2>&1 &
HL_PF_PID=$!
HL_PORT=""
for _ in $(seq 1 30); do
  HL_PORT=$(pf_local_port "$(cat "$HL_PF_LOG")")
  [ -n "$HL_PORT" ] && break
  sleep 1
done
if [ -n "$HL_PORT" ] && curl -sf --retry 5 --retry-connrefused --retry-delay 1 --max-time 10 \
    "http://localhost:${HL_PORT}/" | grep -qiF "headlamp"; then
  pass "Headlamp UI reachable via port-forward (body contains 'headlamp')"
else
  fail "Headlamp UI not reachable via port-forward on localhost:${HL_PORT:-<none>}"
fi
kill "$HL_PF_PID" 2>/dev/null || true
rm -f "$HL_PF_LOG"

# Declarative RBAC proof: the admin-user SA (whose token is in
# headlamp-admin-token.txt) is bound to cluster-admin. Asserted via the
# ClusterRoleBinding's roleRef rather than `kubectl auth can-i --token=<value>` so
# the token never enters argv (security: never put secret values on the command line).
if "${KUBECTL[@]}" get clusterrolebinding headlamp-admin-user -o jsonpath='{.roleRef.name}' 2>/dev/null | grep -qx cluster-admin; then
  pass "Headlamp admin-user is bound to cluster-admin"
else
  fail "Headlamp admin-user ClusterRoleBinding is not bound to cluster-admin"
fi

# --- Metrics-server API (opt-in via TEST_METRICS_SERVER=yes) ---
# Off by default because install-all does NOT install metrics-server; the e2e
# CI workflows run `./scripts/kind-add-metrics-server.sh` first, then set
# TEST_METRICS_SERVER=yes here. Skipping silently when off keeps `make e2e`
# (= install-all + e2e-smoke) green on the default install-all path — same
# rationale as the TEST_MONITORING block below.
if flag_enabled "${TEST_METRICS_SERVER:-}"; then
  # APIService should be Available and serve nodes.
  if "${KUBECTL[@]}" get apiservice v1beta1.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "metrics.k8s.io APIService is Available"
  else
    fail "metrics.k8s.io APIService is not Available"
  fi
  # kubectl top nodes can take ~30s after install before metrics are populated
  if for _ in $(seq 1 12); do
       out=$("${KUBECTL[@]}" top nodes 2>/dev/null) && [ "$(echo "$out" | wc -l)" -ge 2 ] && break
       sleep 5
     done && [ "$(echo "$out" | wc -l)" -ge 2 ]; then
    pass "kubectl top nodes returns >=1 row"
  else
    fail "kubectl top nodes returned no rows after 60s"
  fi
fi

# --- NFS CSI provisioner (opt-in via TEST_NFS=yes) ---
# Off by default because install-all does NOT install in-cluster NFS; the e2e
# CI workflows run `./scripts/kind-add-nfs-incluster.sh` first, then set
# TEST_NFS=yes here. Same opt-in rationale as TEST_METRICS_SERVER above.
if flag_enabled "${TEST_NFS:-}"; then
  "${KUBECTL[@]}" apply -f "$REPO_ROOT/k8s/nfs/pvc-incluster.yaml" >/dev/null
  if "${KUBECTL[@]}" wait pvc/demo-claim-incluster --for=jsonpath='{.status.phase}'=Bound --timeout=120s >/dev/null 2>&1; then
    pass "NFS PVC demo-claim-incluster bound"
  else
    fail "NFS PVC demo-claim-incluster did not bind within 120s"
  fi
  "${KUBECTL[@]}" delete pvc demo-claim-incluster --ignore-not-found --wait=false >/dev/null 2>&1 || true
fi

# --- Host-side NFS provisioner (opt-in via TEST_NFS_HOST=yes) — MANUAL ONLY ---
# NOT wired into any CI workflow: needs a host NFS export (sudo + /etc/exports via
# kind-add-nfs-host-setup.sh) that GitHub-hosted runners can't provide. Distinct
# from the in-cluster NFS path above (TEST_NFS). Run manually after:
#   make nfs-host-setup && make nfs-host-provisioner NFS_SERVER=<host-ip>
#   TEST_NFS_HOST=yes make e2e-smoke
if flag_enabled "${TEST_NFS_HOST:-}"; then
  if "${KUBECTL[@]}" get sc nfs-host >/dev/null 2>&1; then
    pass "nfs-host StorageClass exists"
  else
    fail "nfs-host StorageClass missing — run 'make nfs-host-provisioner NFS_SERVER=<ip>' first"
  fi
  # k8s/nfs/pvc.yaml: PVC demo-claim, storageClassName nfs-host (verified).
  "${KUBECTL[@]}" apply -f "$REPO_ROOT/k8s/nfs/pvc.yaml" >/dev/null
  if "${KUBECTL[@]}" wait pvc/demo-claim --for=jsonpath='{.status.phase}'=Bound --timeout=120s >/dev/null 2>&1; then
    pass "host-NFS PVC demo-claim bound against nfs-host StorageClass"
  else
    fail "host-NFS PVC demo-claim did not bind within 120s"
  fi
  "${KUBECTL[@]}" delete -f "$REPO_ROOT/k8s/nfs/pvc.yaml" --ignore-not-found --wait=false >/dev/null 2>&1 || true
fi

# --- kube-prometheus-stack (opt-in via TEST_MONITORING=yes) ---
# Off by default because install-all does NOT include kube-prometheus-stack;
# weekly monitoring-test.yml runs `make kube-prometheus-stack` first then sets
# TEST_MONITORING=yes here. Skipping silently when off keeps `make e2e` cheap
# on the default install-all path.
if flag_enabled "${TEST_MONITORING:-}"; then
  if "${KUBECTL[@]}" get ns monitoring >/dev/null 2>&1; then
    pass "monitoring namespace exists"
  else
    fail "monitoring namespace missing — run 'make kube-prometheus-stack' before TEST_MONITORING=yes make e2e"
  fi

  if "${KUBECTL[@]}" get svc -n monitoring kube-prometheus-stack-grafana >/dev/null 2>&1; then
    pass "kube-prometheus-stack-grafana Service exists"
  else
    fail "kube-prometheus-stack-grafana Service missing"
  fi

  GRAFANA_IP=""
  for _ in $(seq 1 30); do
    GRAFANA_IP=$("${KUBECTL[@]}" get svc -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$GRAFANA_IP" ] && break
    sleep 2
  done
  if [ -n "$GRAFANA_IP" ]; then
    pass "Grafana Service has LoadBalancer ingress IP ($GRAFANA_IP)"
  else
    fail "Grafana Service did not get a LoadBalancer IP within 60s"
  fi

  # K1.5 route-readiness: an assigned LB IP is not the same as a routable one.
  # Poll Grafana's unauthenticated /api/health (returns {"database":"ok",...})
  # through the control-plane node, mirroring the demo-app docker-exec curl path.
  if [ -n "$GRAFANA_IP" ]; then
    GRAFANA_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 "http://${GRAFANA_IP}/api/health" 2>/dev/null | grep -qF '"database"'; then
        GRAFANA_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$GRAFANA_OK" ]; then
      pass "Grafana /api/health routable at LB IP ${GRAFANA_IP} (body has '\"database\"')"
    else
      fail "Grafana /api/health did not become routable at ${GRAFANA_IP} within 60s"
    fi
  fi

  if [ -n "$("${KUBECTL[@]}" get secret -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' 2>/dev/null)" ]; then
    pass "Grafana admin-password secret is present"
  else
    fail "Grafana admin-password secret missing"
  fi

  # Prometheus is ClusterIP, accessed via port-forward — assert the API
  # surface works through `docker exec` (avoids racing with port-forward).
  if "${KUBECTL[@]}" -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout=60s >/dev/null 2>&1; then
    pass "Prometheus StatefulSet rolled out"
  else
    fail "Prometheus StatefulSet did not roll out within 60s"
  fi

  # Prometheus query API — rollout != functional. Port-forward the ClusterIP svc
  # (ephemeral local port, pf_local_port idiom) and assert /-/healthy plus at least
  # one scrape target reporting health=up (Prometheus self-scrape + kube components).
  PROM_PF_LOG=$(mktemp)
  "${KUBECTL[@]}" -n monitoring port-forward svc/kube-prometheus-stack-prometheus :9090 >"$PROM_PF_LOG" 2>&1 &
  PROM_PF_PID=$!
  PROM_PORT=""
  for _ in $(seq 1 30); do
    PROM_PORT=$(pf_local_port "$(cat "$PROM_PF_LOG")")
    [ -n "$PROM_PORT" ] && break
    sleep 1
  done
  if [ -n "$PROM_PORT" ] && curl -sf --retry 5 --retry-connrefused --retry-delay 1 --max-time 10 \
      "http://localhost:${PROM_PORT}/-/healthy" >/dev/null; then
    pass "Prometheus /-/healthy returns 2xx"
  else
    fail "Prometheus /-/healthy not reachable on localhost:${PROM_PORT:-<none>}"
  fi
  # Targets can take time to come up after install; poll briefly.
  PROM_UP=""
  for _ in $(seq 1 12); do
    if [ -n "$PROM_PORT" ] && \
       UP_COUNT=$(curl -sf --max-time 10 "http://localhost:${PROM_PORT}/api/v1/targets" 2>/dev/null \
         | jq '[.data.activeTargets[]? | select(.health=="up")] | length' 2>/dev/null) \
       && [ "${UP_COUNT:-0}" -ge 1 ]; then
      PROM_UP=yes; break
    fi
    sleep 5
  done
  if [ -n "$PROM_UP" ]; then
    pass "Prometheus has >=1 target with health=up (${UP_COUNT})"
  else
    fail "Prometheus reported no targets with health=up within 60s"
  fi
  kill "$PROM_PF_PID" 2>/dev/null || true
  rm -f "$PROM_PF_LOG"
fi

# --- Gateway API controllers (opt-in via TEST_GATEWAY_API=yes) ---
# Off by default because install-all does NOT enable Gateway API. Run
# `make gateway-traefik` and/or `make gateway-istio` first, then
# TEST_GATEWAY_API=yes make e2e-smoke. See docs/gateway-api-ingress.md.
if flag_enabled "${TEST_GATEWAY_API:-}"; then
  # Traefik Gateway API provider: GatewayClass Accepted + HTTPRoutes reach the
  # SAME demo backends on *.gw.localdev.me via the Traefik LB IP — same pod as
  # classic Ingress, proving the two providers coexist.
  if "${KUBECTL[@]}" get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "Traefik GatewayClass is Accepted"
  else
    fail "Traefik GatewayClass not Accepted — run 'make gateway-traefik' first"
  fi
  check_curl "helloweb via Traefik Gateway API"       "http://${INGRESS_IP}/"        "Hello, world!"  -H "Host: helloweb.gw.localdev.me"
  check_curl "golang /healthz via Traefik Gateway API" "http://${INGRESS_IP}/healthz" '"health":"ok"'  -H "Host: golang.gw.localdev.me"

  # Istio Gateway controller: coexists with Traefik (distinct controllerName),
  # gets its OWN LoadBalancer IP from cloud-provider-kind, fronts the SAME apps.
  if "${KUBECTL[@]}" get gatewayclass istio -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "Istio GatewayClass is Accepted"
  else
    fail "Istio GatewayClass not Accepted — run 'make gateway-istio' first"
  fi
  ISTIO_GW_IP=""
  for _ in $(seq 1 30); do
    ISTIO_GW_IP=$("${KUBECTL[@]}" -n default get svc istio-istio -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$ISTIO_GW_IP" ] && break
    sleep 2
  done
  if [ -n "$ISTIO_GW_IP" ]; then
    pass "Istio gateway Service has its own LoadBalancer IP ($ISTIO_GW_IP)"
    # K1.5 route-readiness: assigned IP != routable; poll until it serves.
    ISTIO_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${ISTIO_GW_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        ISTIO_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$ISTIO_OK" ]; then
      pass "helloweb reachable via Istio Gateway at ${ISTIO_GW_IP} (same backend as Traefik)"
    else
      fail "Istio Gateway at ${ISTIO_GW_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via Istio Gateway" "http://${ISTIO_GW_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "Istio gateway Service istio-istio got no LoadBalancer IP within 60s"
  fi

  # NGINX Gateway Fabric: coexists with Traefik+Istio (distinct controllerName),
  # provisions a per-Gateway nginx data plane ("ngf-nginx") that gets its OWN
  # LoadBalancer IP from cloud-provider-kind, fronting the SAME apps.
  if "${KUBECTL[@]}" get gatewayclass nginx -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "NGINX Gateway Fabric GatewayClass is Accepted"
  else
    fail "NGINX GatewayClass not Accepted — run 'make gateway-nginx' first"
  fi
  NGF_GW_IP=""
  for _ in $(seq 1 30); do
    NGF_GW_IP=$("${KUBECTL[@]}" -n default get svc ngf-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$NGF_GW_IP" ] && break
    sleep 2
  done
  if [ -n "$NGF_GW_IP" ]; then
    pass "NGF gateway Service has its own LoadBalancer IP ($NGF_GW_IP)"
    # K1.5 route-readiness: assigned IP != routable; poll until it serves.
    NGF_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${NGF_GW_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        NGF_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$NGF_OK" ]; then
      pass "helloweb reachable via NGF Gateway at ${NGF_GW_IP} (same backend as Traefik)"
    else
      fail "NGF Gateway at ${NGF_GW_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via NGF Gateway" "http://${NGF_GW_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "NGF gateway Service ngf-nginx got no LoadBalancer IP within 60s"
  fi

  # Project Contour (Gateway provisioner): distinct controllerName, provisions a
  # per-Gateway Envoy ("envoy-contour") that gets its OWN LB IP, same backends.
  if "${KUBECTL[@]}" get gatewayclass contour -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "Contour GatewayClass is Accepted"
  else
    fail "Contour GatewayClass not Accepted — run 'make gateway-contour' first"
  fi
  CONTOUR_GW_IP=""
  for _ in $(seq 1 30); do
    CONTOUR_GW_IP=$("${KUBECTL[@]}" -n default get svc envoy-contour -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$CONTOUR_GW_IP" ] && break
    sleep 2
  done
  if [ -n "$CONTOUR_GW_IP" ]; then
    pass "Contour Envoy Service has its own LoadBalancer IP ($CONTOUR_GW_IP)"
    # K1.5 route-readiness: assigned IP != routable; poll until it serves.
    CONTOUR_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${CONTOUR_GW_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        CONTOUR_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$CONTOUR_OK" ]; then
      pass "helloweb reachable via Contour Gateway at ${CONTOUR_GW_IP} (same backend as Traefik)"
    else
      fail "Contour Gateway at ${CONTOUR_GW_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via Contour Gateway" "http://${CONTOUR_GW_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "Contour Envoy Service envoy-contour got no LoadBalancer IP within 60s"
  fi

  # Envoy Gateway (CNCF): distinct controllerName, provisions a per-Gateway Envoy
  # in envoy-gateway-system with a GENERATED name (discovered by the owning-gateway
  # labels, not a fixed name) that gets its OWN LB IP, same backends.
  if "${KUBECTL[@]}" get gatewayclass envoy -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "Envoy Gateway GatewayClass is Accepted"
  else
    fail "Envoy Gateway GatewayClass not Accepted — run 'make gateway-envoy' first"
  fi
  EG_SVC=""
  for _ in $(seq 1 30); do
    EG_SVC=$("${KUBECTL[@]}" -n envoy-gateway-system get svc \
      -l gateway.envoyproxy.io/owning-gateway-namespace=default,gateway.envoyproxy.io/owning-gateway-name=eg \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    [ -n "$EG_SVC" ] && break
    sleep 2
  done
  EG_GW_IP=""
  if [ -n "$EG_SVC" ]; then
    for _ in $(seq 1 30); do
      EG_GW_IP=$("${KUBECTL[@]}" -n envoy-gateway-system get svc "$EG_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
      [ -n "$EG_GW_IP" ] && break
      sleep 2
    done
  fi
  if [ -n "$EG_GW_IP" ]; then
    pass "Envoy Gateway Service ($EG_SVC) has its own LoadBalancer IP ($EG_GW_IP)"
    EG_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${EG_GW_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        EG_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$EG_OK" ]; then
      pass "helloweb reachable via Envoy Gateway at ${EG_GW_IP} (same backend as Traefik)"
    else
      fail "Envoy Gateway at ${EG_GW_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via Envoy Gateway" "http://${EG_GW_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "Envoy Gateway Service got no LoadBalancer IP within 60s"
  fi

  # kgateway (CNCF, formerly Gloo OSS): distinct controllerName, provisions a
  # per-Gateway Envoy ("kgw") that gets its OWN LB IP, same backends.
  if "${KUBECTL[@]}" get gatewayclass kgateway -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "kgateway GatewayClass is Accepted"
  else
    fail "kgateway GatewayClass not Accepted — run 'make gateway-kgateway' first"
  fi
  KGW_IP=""
  for _ in $(seq 1 30); do
    KGW_IP=$("${KUBECTL[@]}" -n default get svc kgw -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    [ -n "$KGW_IP" ] && break
    sleep 2
  done
  if [ -n "$KGW_IP" ]; then
    pass "kgateway gateway Service has its own LoadBalancer IP ($KGW_IP)"
    KGW_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${KGW_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        KGW_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$KGW_OK" ]; then
      pass "helloweb reachable via kgateway at ${KGW_IP} (same backend as Traefik)"
    else
      fail "kgateway at ${KGW_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via kgateway" "http://${KGW_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "kgateway gateway Service kgw got no LoadBalancer IP within 60s"
  fi

  # Kong (KIC, unmanaged Gateway): distinct controllerName; the data plane is the
  # chart's single kong proxy LoadBalancer Service (discovered by type, since its
  # name varies across chart versions), not a per-Gateway one. Same backends.
  if "${KUBECTL[@]}" get gatewayclass kong -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null | grep -q '^True$'; then
    pass "Kong GatewayClass is Accepted"
  else
    fail "Kong GatewayClass not Accepted — run 'make gateway-kong' first"
  fi
  KONG_SVC=""
  for _ in $(seq 1 30); do
    KONG_SVC=$("${KUBECTL[@]}" -n kong get svc \
      -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "")
    [ -n "$KONG_SVC" ] && break
    sleep 2
  done
  KONG_IP=""
  if [ -n "$KONG_SVC" ]; then
    for _ in $(seq 1 30); do
      KONG_IP=$("${KUBECTL[@]}" -n kong get svc "$KONG_SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
      [ -n "$KONG_IP" ] && break
      sleep 2
    done
  fi
  if [ -n "$KONG_IP" ]; then
    pass "Kong proxy Service ($KONG_SVC) has its own LoadBalancer IP ($KONG_IP)"
    KONG_OK=""
    for _ in $(seq 1 30); do
      if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${KONG_IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
        KONG_OK=yes; break
      fi
      sleep 2
    done
    if [ -n "$KONG_OK" ]; then
      pass "helloweb reachable via Kong at ${KONG_IP} (same backend as Traefik)"
    else
      fail "Kong at ${KONG_IP} did not route to helloweb within 60s"
    fi
    check_curl "golang /healthz via Kong" "http://${KONG_IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
  else
    fail "Kong proxy Service got no LoadBalancer IP within 60s"
  fi
fi

# --- Alternative classic Ingress controllers (opt-in via TEST_INGRESS_ALT=yes) ---
# Off by default because install-all wires only Traefik. Run `make ingress-haproxy`
# and/or `make ingress-nginx` first, then TEST_INGRESS_ALT=yes make e2e-smoke.
# Each alternative controller registers a distinct ingressClassName and gets its
# OWN LoadBalancer IP, fronting the SAME demo apps as Traefik.
if flag_enabled "${TEST_INGRESS_ALT:-}"; then
  echo ""
  echo "=== Alternative classic Ingress controllers (TEST_INGRESS_ALT=yes) ==="
  # name|namespace|ingressClassName — discover each controller's LB Service by type.
  for spec in "HAProxy|haproxy-controller|haproxy" "NGINX Inc.|nginx-ingress|nginx"; do
    NAME="${spec%%|*}"; rest="${spec#*|}"; NS="${rest%%|*}"; CLASS="${rest##*|}"
    if "${KUBECTL[@]}" get ingressclass "$CLASS" >/dev/null 2>&1; then
      pass "$NAME IngressClass '$CLASS' exists"
    else
      fail "$NAME IngressClass '$CLASS' missing — run its make target first"
    fi
    SVC=""
    for _ in $(seq 1 30); do
      SVC=$("${KUBECTL[@]}" -n "$NS" get svc \
        -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "")
      [ -n "$SVC" ] && break
      sleep 2
    done
    IP=""
    if [ -n "$SVC" ]; then
      for _ in $(seq 1 30); do
        IP=$("${KUBECTL[@]}" -n "$NS" get svc "$SVC" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        [ -n "$IP" ] && break
        sleep 2
      done
    fi
    if [ -n "$IP" ]; then
      pass "$NAME controller Service ($SVC) has its own LoadBalancer IP ($IP)"
      OK=""
      for _ in $(seq 1 30); do
        if docker exec "$KIND_NODE" curl -sf --max-time 5 -H "Host: helloweb.localdev.me" "http://${IP}/" 2>/dev/null | grep -qF "Hello, world!"; then
          OK=yes; break
        fi
        sleep 2
      done
      if [ -n "$OK" ]; then
        pass "helloweb reachable via $NAME at ${IP} (same backend as Traefik)"
      else
        fail "$NAME at ${IP} did not route to helloweb within 60s"
      fi
      check_curl "golang /healthz via $NAME" "http://${IP}/healthz" '"health":"ok"' -H "Host: golang.localdev.me"
    else
      fail "$NAME controller Service got no LoadBalancer IP within 60s"
    fi
  done
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
