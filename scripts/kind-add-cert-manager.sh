#!/usr/bin/env bash
# Install cert-manager and bootstrap a LOCAL self-signed CA so workload TLS
# certs can be issued entirely offline — no Let's Encrypt, no public DNS, no
# secrets. The `local-ca` ClusterIssuer then signs leaf certs for *.localdev.me
# (make tls) and per-gateway *.<ip>.sslip.io names (make tls-all). Trust the
# exported CA cert to get HTTPS with no `-k`. See the README "HTTPS with a
# locally-trusted CA" section and docs/gateway-api-ingress.md.
#
# Requires `make install-all` first (cluster up) and the Gateway API CRDs
# present — cert-manager's Gateway support (config.enableGatewayAPI=true) needs
# them at startup. `make tls-all` installs the CRDs if absent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"
# Where to write the CA cert for `curl --cacert` (repo root, gitignored).
CA_CERT_FILE="${CA_CERT_FILE:-lab-ca.crt}"

# renovate: datasource=docker depName=quay.io/jetstack/charts/cert-manager
CERT_MANAGER_VERSION=v1.20.2
CERT_MANAGER_CHART="oci://quay.io/jetstack/charts/cert-manager"

echo "=== Installing cert-manager ${CERT_MANAGER_VERSION} (Gateway API support enabled) ==="
# config.enableGatewayAPI=true is the CURRENT flag (cert-manager >= 1.15); the
# old --feature-gates=ExperimentalGatewayAPISupport was removed. crds.enabled
# installs cert-manager's own CRDs. Gateway support also needs the Gateway API
# CRDs already present in the cluster.
"${HELM[@]}" upgrade --install cert-manager "$CERT_MANAGER_CHART" \
    --version "${CERT_MANAGER_VERSION}" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set config.enableGatewayAPI=true \
    --wait --timeout "${TIMEOUT}"
"${KUBECTL[@]}" -n cert-manager rollout status deploy/cert-manager-webhook --timeout="${TIMEOUT}"

echo "=== Bootstrapping the local CA (selfSigned -> CA -> local-ca ClusterIssuer) ==="
# The validating webhook can briefly refuse admission for a few seconds after
# the Deployment reports Ready; retry the apply until it sticks (same race the
# MetalLB IPAddressPool apply guards against).
for _ in $(seq 1 30); do
  "${KUBECTL[@]}" apply -f k8s/tls/ca-bootstrap.yaml >/dev/null 2>&1 && break
  sleep 2
done
"${KUBECTL[@]}" apply -f k8s/tls/ca-bootstrap.yaml
"${KUBECTL[@]}" wait clusterissuer/local-ca --for=condition=Ready --timeout="${TIMEOUT}"

echo "=== Exporting the CA certificate to ${CA_CERT_FILE} ==="
"${KUBECTL[@]}" get secret lab-root-ca -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > "${CA_CERT_FILE}"
echo "Wrote ${CA_CERT_FILE} ($(wc -c < "${CA_CERT_FILE}" | tr -d ' ') bytes). Trust it to drop the '-k':"
echo "  per-request:    curl --cacert ${CA_CERT_FILE} https://helloweb.localdev.me/"
echo "  system (Linux): sudo cp ${CA_CERT_FILE} /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
echo ""
echo "Next: 'make tls' (Traefik *.localdev.me HTTPS) and/or 'make tls-all' (per-gateway *.sslip.io HTTPS)."
