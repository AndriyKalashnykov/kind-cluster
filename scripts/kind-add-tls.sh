#!/usr/bin/env bash
# Wire trusted HTTPS onto the DEFAULT Traefik front door with a local-CA cert
# for *.localdev.me — the classic Traefik Ingress (demo-apps). Traefik terminates
# at its websecure entrypoint (hostPort 443), so reach the demo apps over HTTPS
# at https://<app>.localdev.me/ via localhost. Requires `make cert-manager` first.
#
# Scope note: this covers Traefik's CLASSIC Ingress path (the same Traefik pod
# that fronts every demo app on *.localdev.me). The opt-in Gateway API
# controllers (incl. Traefik's own Gateway provider) get trusted HTTPS via
# `make tls-all` (per-LB-IP *.sslip.io). See README "HTTPS with a locally-trusted CA".
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

echo ""
echo "Trusted HTTPS on the Traefik front door. After 'make cert-manager' exported ${CA_CERT_FILE}:"
echo "  curl --cacert ${CA_CERT_FILE} --resolve helloweb.localdev.me:443:127.0.0.1 https://helloweb.localdev.me/"
echo "For the opt-in Gateway API controllers, run 'make tls-all' (per-LB-IP *.sslip.io HTTPS)."
