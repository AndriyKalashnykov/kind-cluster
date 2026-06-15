#!/usr/bin/env bash
# Wire trusted HTTPS onto BOTH of the DEFAULT Traefik front doors with one
# local-CA cert (covers *.localdev.me AND *.gw.localdev.me). Traefik terminates
# TLS at its websecure entrypoint (container port 8443, exposed on hostPort 443),
# so reach the demo apps over HTTPS at https://<app>.localdev.me/ (classic
# Ingress) and https://<app>.gw.localdev.me/ (Gateway-API provider) via
# localhost. Requires `make cert-manager` first.
#
# Scope note: this covers the SHARED Traefik pod's two paths:
#   * classic Ingress      — *.localdev.me     (Ingress.spec.tls)
#   * Gateway-API provider — *.gw.localdev.me  (Gateway HTTPS listener on the
#                            websecure entrypoint, port 8443 — only if
#                            `make gateway-traefik` was run)
# Both terminate on the websecure entrypoint and coexist via per-SNI cert
# resolution (the entrypoint's `http.tls=true` default is overridden per router
# by each path's own cert). The Gateway listener port MUST equal the entrypoint
# CONTAINER port (8443), not the hostPort (443) — mirroring the working HTTP
# listener, which uses 8000, not 80. The OTHER opt-in Gateway API controllers
# get trusted HTTPS via `make tls-all` (per-LB-IP *.sslip.io). See README
# "HTTPS with a locally-trusted CA".
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-2m}"
CA_CERT_FILE="${CA_CERT_FILE:-lab-ca.crt}"

if ! "${KUBECTL[@]}" get clusterissuer local-ca >/dev/null 2>&1; then
  echo "Error: local-ca ClusterIssuer not found. Run 'make cert-manager' first." >&2
  exit 1
fi

echo "=== Issuing the *.localdev.me cert from local-ca ==="
"${KUBECTL[@]}" apply -f k8s/tls/cert-localdev.yaml
"${KUBECTL[@]}" wait certificate/lab-localdev-tls -n default --for=condition=Ready --timeout="${TIMEOUT}"

echo "=== Wiring TLS into the classic Traefik Ingress (demo-apps) ==="
"${KUBECTL[@]}" patch ingress demo-apps -n default --type=merge -p \
  '{"spec":{"tls":[{"hosts":["demo.localdev.me","helloweb.localdev.me","golang.localdev.me","foo.localdev.me"],"secretName":"lab-localdev-tls"}]}}'

# Wire HTTPS onto Traefik's Gateway-API provider too, IF it's installed
# (`make gateway-traefik`). The websecure entrypoint's CONTAINER port is 8443
# (hostPort 443) — a Traefik Gateway listener matches the entrypoint by its
# container port, so the HTTPS listener MUST be 8443 (the working HTTP listener
# uses 8000, not 80). The same lab-localdev-tls Secret carries the
# *.gw.localdev.me SAN; the gw-* HTTPRoutes (no sectionName) attach to this
# listener automatically. Idempotent: only add the listener once.
if "${KUBECTL[@]}" get gateway traefik-gateway -n default >/dev/null 2>&1; then
  echo "=== Wiring HTTPS onto Traefik's Gateway-API provider (*.gw.localdev.me, websecure/8443) ==="
  if ! "${KUBECTL[@]}" get gateway traefik-gateway -n default \
        -o jsonpath='{.spec.listeners[*].name}' | tr ' ' '\n' | grep -qx websecure; then
    "${KUBECTL[@]}" patch gateway traefik-gateway -n default --type=json -p \
      '[{"op":"add","path":"/spec/listeners/-","value":{"name":"websecure","hostname":"*.gw.localdev.me","protocol":"HTTPS","port":8443,"allowedRoutes":{"namespaces":{"from":"All"}},"tls":{"mode":"Terminate","certificateRefs":[{"kind":"Secret","name":"lab-localdev-tls"}]}}}]'
  fi
fi

echo ""
echo "Trusted HTTPS on the Traefik front door(s). After 'make cert-manager' exported ${CA_CERT_FILE}:"
echo "  curl --cacert ${CA_CERT_FILE} --resolve helloweb.localdev.me:443:127.0.0.1    https://helloweb.localdev.me/"
echo "  curl --cacert ${CA_CERT_FILE} --resolve helloweb.gw.localdev.me:443:127.0.0.1 https://helloweb.gw.localdev.me/   # if gateway-traefik installed"
echo "For the OTHER opt-in Gateway API controllers, run 'make tls-all' (per-LB-IP *.sslip.io HTTPS)."
