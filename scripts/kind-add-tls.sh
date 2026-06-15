#!/usr/bin/env bash
# Wire trusted HTTPS onto the DEFAULT Traefik front door with a local-CA cert
# for *.localdev.me / *.gw.localdev.me — the classic Ingress (demo-apps) AND, if
# the Traefik Gateway API provider is enabled (make gateway-traefik), its
# Gateway too. Both terminate at Traefik's websecure entrypoint (hostPort 443),
# so reach them at https://<app>.localdev.me/ via localhost. Requires
# `make cert-manager` first. See README "HTTPS with a locally-trusted CA".
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

echo "=== Issuing the *.localdev.me / *.gw.localdev.me cert from local-ca ==="
"${KUBECTL[@]}" apply -f k8s/tls/cert-localdev.yaml
"${KUBECTL[@]}" wait certificate/lab-localdev-tls -n default --for=condition=Ready --timeout="${TIMEOUT}"

echo "=== Wiring TLS into the classic Traefik Ingress (demo-apps) ==="
"${KUBECTL[@]}" patch ingress demo-apps -n default --type=merge -p \
  '{"spec":{"tls":[{"hosts":["demo.localdev.me","helloweb.localdev.me","golang.localdev.me","foo.localdev.me"],"secretName":"lab-localdev-tls"}]}}'

# If the Traefik Gateway API provider is enabled, add an HTTPS listener so
# https://<app>.gw.localdev.me/ terminates with the same cert. The existing
# gw-* HTTPRoutes (parentRef: traefik-gateway, hosts *.gw.localdev.me) attach to
# it automatically. Idempotent: skip if the listener already exists.
if "${KUBECTL[@]}" get gateway traefik-gateway -n default >/dev/null 2>&1; then
  if "${KUBECTL[@]}" get gateway traefik-gateway -n default \
       -o jsonpath='{.spec.listeners[*].name}' | tr ' ' '\n' | grep -qx https; then
    echo "=== Traefik Gateway already has an https listener — leaving as is ==="
  else
    echo "=== Adding an HTTPS listener to the Traefik Gateway ==="
    "${KUBECTL[@]}" patch gateway traefik-gateway -n default --type=json -p \
      '[{"op":"add","path":"/spec/listeners/-","value":{"name":"https","hostname":"*.gw.localdev.me","protocol":"HTTPS","port":443,"allowedRoutes":{"namespaces":{"from":"Same"}},"tls":{"mode":"Terminate","certificateRefs":[{"kind":"Secret","name":"lab-localdev-tls"}]}}}]'
  fi
fi

echo ""
echo "Trusted HTTPS on the Traefik front door. After 'make cert-manager' exported ${CA_CERT_FILE}:"
echo "  curl --cacert ${CA_CERT_FILE} --resolve helloweb.localdev.me:443:127.0.0.1 https://helloweb.localdev.me/"
echo "  curl --cacert ${CA_CERT_FILE} --resolve helloweb.gw.localdev.me:443:127.0.0.1 https://helloweb.gw.localdev.me/   # if 'make gateway-traefik' was run"
