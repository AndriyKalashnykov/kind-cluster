#!/bin/bash
# Deploy a httpd backend exposed via Traefik at http://demo.localdev.me/.
# Used by `make install-all` and CI as the smoke-test target for the
# ingress data path. Idempotent (re-running install-all must not error).
#
# The Traefik chart already creates a LoadBalancer Service — no service-type
# patch needed (the previous ingress-nginx flow patched it post-install).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

TIMEOUT=${1:-180s}

echo "waiting for Traefik service to get External-IP"
for _ in $(seq 1 90); do
    "${KUBECTL[@]}" get service/traefik -n traefik --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
"${KUBECTL[@]}" get service/traefik -n traefik --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: Traefik LoadBalancer did not get an External-IP after 180s"; "${KUBECTL[@]}" get svc -n traefik traefik; exit 1; }
service_ip=$("${KUBECTL[@]}" get services traefik -n traefik -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "Traefik External-IP: ${service_ip}"

echo "deploying a httpd web server and the associated service"
DEMO_SVC_NAME=demo-localhost
DEMO_SVC_PORT=80
# Use dry-run + apply for idempotency (re-running install-all must not error)
"${KUBECTL[@]}" create deployment demo-localhost --image=httpd --port=${DEMO_SVC_PORT} --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
echo "waiting for httpd pods"
"${KUBECTL[@]}" wait deployment -n default demo-localhost --for condition=Available=True --timeout="${TIMEOUT}"
"${KUBECTL[@]}" expose deployment ${DEMO_SVC_NAME} --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

echo "creating an ingress resource and mapping demo.localdev.me to localhost"
"${KUBECTL[@]}" create ingress demo-localhost --class=traefik --rule="demo.localdev.me/*=${DEMO_SVC_NAME}:${DEMO_SVC_PORT}" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

echo "waiting for ingress demo-localhost"
wait_period=0
hostname=""
while [ -z "$hostname" ]; do
  echo "Waiting for hostname ..."
  hostname=$("${KUBECTL[@]}" get --namespace default ingress/demo-localhost --template="{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}")
  if [ -z "$hostname" ];then
    sleep 10
    wait_period=$((wait_period+10))
  fi

  wait_timeout=${TIMEOUT//[^0-9]/}
  if [ "$wait_period" -gt "$wait_timeout" ];then
    echo "Didn't get the hostname, timeout reached"
    break
  fi
done
echo "ingress demo-localhost hostname: $hostname"

# demo.localdev.me NXDOMAIN on many hosts (GH runners included); curl the
# Traefik LoadBalancer IP directly from INSIDE the kind control-plane
# node with an explicit Host header. Retry up to 30s for async rule propagation.
KIND_NODE=$(docker ps --filter label=io.x-k8s.kind.role=control-plane --format '{{.Names}}' | head -1)
INGRESS_IP=$("${KUBECTL[@]}" get svc -n traefik traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in $(seq 1 15); do
    RESP=$(docker exec "${KIND_NODE}" curl -sf --max-time 5 -H "Host: demo.localdev.me" "http://${INGRESS_IP}:80/" 2>/dev/null) && { echo "$RESP" | head -c 200; echo; break; }
    sleep 2
done
[ -n "${RESP:-}" ] || echo "(curl http://${INGRESS_IP} via ${KIND_NODE} with Host demo.localdev.me failed after 30s)"
