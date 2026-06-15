#!/usr/bin/env bash
# Issue per-LB-IP trusted certs and wire HTTPS onto every INSTALLED opt-in
# Gateway API controller (Istio, NGF, Contour, Envoy Gateway, kgateway, Kong).
# Each has its own cloud-provider-kind LoadBalancer IP; sslip.io turns that IP
# into a resolvable hostname (helloweb.<dashed-ip>.sslip.io -> that IP), so
# https://helloweb.<dashed-ip>.sslip.io/ terminates with a CA-trusted cert and
# no `-k`. The default Traefik front door uses *.gw.localdev.me and is wired by
# `make tls`. Requires `make cert-manager` first (the local-ca ClusterIssuer).
# See the README "HTTPS with a locally-trusted CA" section.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-2m}"
CA_CERT_FILE="${CA_CERT_FILE:-lab-ca.crt}"

if ! "${KUBECTL[@]}" get clusterissuer local-ca >/dev/null 2>&1; then
  echo "Error: local-ca ClusterIssuer not found. Run 'make cert-manager' first." >&2
  exit 1
fi

# Resolve a controller's LoadBalancer IP from its data-plane Service. The
# discovery differs per controller (fixed name / owning-gateway label / by type)
# — mirrors scripts/e2e-smoke.sh.
gw_lb_ip() {  # <svc-namespace> <discovery>  -> prints IP (or empty)
  local ns="$1" disc="$2" svc=""
  case "$disc" in
    name:*)  svc="${disc#name:}" ;;
    label:*) svc=$("${KUBECTL[@]}" -n "$ns" get svc -l "${disc#label:}" \
               -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "") ;;
    type:*)  svc=$("${KUBECTL[@]}" -n "$ns" get svc \
               -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "") ;;
  esac
  [ -n "$svc" ] && "${KUBECTL[@]}" -n "$ns" get svc "$svc" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
}

# gateway-name | data-plane-svc-namespace | discovery
# (every Gateway resource itself lives in the `default` namespace, so the certs
# and HTTPRoutes go there too — same namespace as the backend Services.)
SPECS=(
  "istio|default|name:istio-istio"
  "ngf|default|name:ngf-nginx"
  "contour|default|name:envoy-contour"
  "eg|envoy-gateway-system|label:gateway.envoyproxy.io/owning-gateway-name=eg"
  "kgw|default|name:kgw"
  "kong|kong|type:LoadBalancer"
)

WIRED=0
for spec in "${SPECS[@]}"; do
  GW="${spec%%|*}"; rest="${spec#*|}"; NS="${rest%%|*}"; DISC="${rest##*|}"
  "${KUBECTL[@]}" get gateway "$GW" -n default >/dev/null 2>&1 || { echo "skip $GW (not installed)"; continue; }

  IP=""; for _ in $(seq 1 30); do IP=$(gw_lb_ip "$NS" "$DISC"); [ -n "$IP" ] && break; sleep 2; done
  if [ -z "$IP" ]; then echo "WARN $GW: no LoadBalancer IP yet — skipping"; continue; fi
  DASHED=$(dash_ip "$IP")
  echo "=== $GW: *.${DASHED}.sslip.io @ ${IP} ==="

  # Leaf cert: wildcard sslip.io SAN + the IP itself as an IP SAN.
  cat <<EOF | "${KUBECTL[@]}" apply -f - >/dev/null
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: ${GW}-sslip-tls, namespace: default }
spec:
  secretName: ${GW}-sslip-tls
  dnsNames: ["*.${DASHED}.sslip.io"]
  ipAddresses: ["${IP}"]
  issuerRef: { name: local-ca, kind: ClusterIssuer, group: cert-manager.io }
EOF
  "${KUBECTL[@]}" wait certificate/"${GW}"-sslip-tls -n default --for=condition=Ready --timeout="${TIMEOUT}" >/dev/null

  # HTTPS listener on the Gateway (idempotent).
  if ! "${KUBECTL[@]}" get gateway "$GW" -n default -o jsonpath='{.spec.listeners[*].name}' \
        | tr ' ' '\n' | grep -qx https-sslip; then
    "${KUBECTL[@]}" patch gateway "$GW" -n default --type=json -p \
      "[{\"op\":\"add\",\"path\":\"/spec/listeners/-\",\"value\":{\"name\":\"https-sslip\",\"hostname\":\"*.${DASHED}.sslip.io\",\"protocol\":\"HTTPS\",\"port\":443,\"allowedRoutes\":{\"namespaces\":{\"from\":\"All\"}},\"tls\":{\"mode\":\"Terminate\",\"certificateRefs\":[{\"kind\":\"Secret\",\"name\":\"${GW}-sslip-tls\"}]}}}]" >/dev/null
  fi

  # Per-app HTTPRoutes matching the sslip.io hostnames.
  cat <<EOF | "${KUBECTL[@]}" apply -f - >/dev/null
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW}-sslip-helloweb, namespace: default }
spec:
  parentRefs: [{ name: ${GW} }]
  hostnames: ["$(sslip_host helloweb "$IP")"]
  rules: [{ backendRefs: [{ name: helloweb, port: 80 }] }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW}-sslip-golang, namespace: default }
spec:
  parentRefs: [{ name: ${GW} }]
  hostnames: ["$(sslip_host golang "$IP")"]
  rules: [{ backendRefs: [{ name: golang-hello-world-web-service, port: 8080 }] }]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: ${GW}-sslip-foo, namespace: default }
spec:
  parentRefs: [{ name: ${GW} }]
  hostnames: ["$(sslip_host foo "$IP")"]
  rules: [{ backendRefs: [{ name: foo-service, port: 5678 }] }]
EOF
  echo "  curl --cacert ${CA_CERT_FILE} https://$(sslip_host helloweb "$IP")/"
  WIRED=$((WIRED + 1))
done

# Alternative CLASSIC Ingress controllers (HAProxy, NGINX Inc.). Same idea, but
# classic Ingress terminates TLS via `spec.tls` referencing a Secret in the
# Ingress's own namespace (default), so we apply a dedicated sslip.io Ingress
# per class with TLS + per-app host rules. ingressClassName selects the
# controller; each has its own cloud-provider-kind LB IP.
# class | controller-service-namespace (Service discovered by type=LoadBalancer)
ING_SPECS=(
  "haproxy|haproxy-controller"
  "nginx|nginx-ingress"
)
for spec in "${ING_SPECS[@]}"; do
  CLASS="${spec%%|*}"; NS="${spec#*|}"
  "${KUBECTL[@]}" get ingressclass "$CLASS" >/dev/null 2>&1 || { echo "skip ingress/$CLASS (not installed)"; continue; }

  IP=""; for _ in $(seq 1 30); do IP=$(gw_lb_ip "$NS" "type:LoadBalancer"); [ -n "$IP" ] && break; sleep 2; done
  if [ -z "$IP" ]; then echo "WARN ingress/$CLASS: no LoadBalancer IP yet — skipping"; continue; fi
  DASHED=$(dash_ip "$IP")
  echo "=== ingress/$CLASS: *.${DASHED}.sslip.io @ ${IP} ==="

  cat <<EOF | "${KUBECTL[@]}" apply -f - >/dev/null
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: ${CLASS}-ingress-sslip-tls, namespace: default }
spec:
  secretName: ${CLASS}-ingress-sslip-tls
  dnsNames: ["*.${DASHED}.sslip.io"]
  ipAddresses: ["${IP}"]
  issuerRef: { name: local-ca, kind: ClusterIssuer, group: cert-manager.io }
EOF
  "${KUBECTL[@]}" wait certificate/"${CLASS}"-ingress-sslip-tls -n default --for=condition=Ready --timeout="${TIMEOUT}" >/dev/null

  cat <<EOF | "${KUBECTL[@]}" apply -f - >/dev/null
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: demo-sslip-${CLASS}, namespace: default }
spec:
  ingressClassName: ${CLASS}
  tls:
    - hosts: ["$(sslip_host helloweb "$IP")", "$(sslip_host golang "$IP")", "$(sslip_host foo "$IP")"]
      secretName: ${CLASS}-ingress-sslip-tls
  rules:
    - host: "$(sslip_host helloweb "$IP")"
      http: { paths: [{ path: /, pathType: Prefix, backend: { service: { name: helloweb, port: { number: 80 } } } }] }
    - host: "$(sslip_host golang "$IP")"
      http: { paths: [{ path: /, pathType: Prefix, backend: { service: { name: golang-hello-world-web-service, port: { number: 8080 } } } }] }
    - host: "$(sslip_host foo "$IP")"
      http: { paths: [{ path: /, pathType: Prefix, backend: { service: { name: foo-service, port: { number: 5678 } } } }] }
EOF
  echo "  curl --cacert ${CA_CERT_FILE} https://$(sslip_host helloweb "$IP")/"
  WIRED=$((WIRED + 1))
done

echo ""
echo "Wired trusted HTTPS on ${WIRED} front door(s) (Gateway API controllers + classic Ingress) via *.sslip.io."
[ "$WIRED" -gt 0 ] || echo "  (none installed — run e.g. 'make gateway-istio' or 'make ingress-haproxy' first, then re-run 'make tls-all')."
