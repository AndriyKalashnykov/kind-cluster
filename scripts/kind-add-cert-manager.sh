#!/usr/bin/env bash
# Install cert-manager and bootstrap a LOCAL self-signed CA so workload TLS
# certs can be issued entirely offline — no Let's Encrypt, no public DNS, no
# secrets. The `local-ca` ClusterIssuer then signs leaf certs for *.localdev.me
# (make tls) and per-gateway *.<ip>.sslip.io names (make tls-all). Trust the
# exported CA cert to get HTTPS with no `-k`. See the README "HTTPS with a
# locally-trusted CA" section and docs/gateway-api-ingress.md.
#
# Gateway API support (ENABLE_GATEWAY_API=true, the default) lets cert-manager
# sign Gateway listener certs — `make tls-all`'s per-gateway *.sslip.io path.
# The cert-manager CONTROLLER hard-fails at startup when enableGatewayAPI=true
# but the Gateway API CRDs are absent, so that path requires the CRDs present
# (`make tls-all` installs them if absent). For a CLASSIC-Ingress-only TLS path
# (e.g. the MetalLB e2e, which has no Gateway resources), set
# ENABLE_GATEWAY_API=false: cert-manager then needs no Gateway API CRDs, which
# also avoids installing the Gateway API `safe-upgrades` ValidatingAdmissionPolicy
# that would block a later cloud-provider-kind startup from reconciling its own
# (older, standard-channel) embedded Gateway API CRDs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"
# Where to write the CA cert for `curl --cacert` (repo root, gitignored).
CA_CERT_FILE="${CA_CERT_FILE:-lab-ca.crt}"
# Enable cert-manager's Gateway API support. Default true (the `make tls-all`
# per-gateway path needs it AND the Gateway API CRDs present). Set false for a
# classic-Ingress-only TLS path that has no Gateway resources (MetalLB e2e) —
# avoids the Gateway API CRD requirement and its safe-upgrades VAP. See header.
ENABLE_GATEWAY_API="${ENABLE_GATEWAY_API:-true}"

# renovate: datasource=docker depName=quay.io/jetstack/charts/cert-manager
CERT_MANAGER_VERSION=v1.20.3
CERT_MANAGER_CHART="oci://quay.io/jetstack/charts/cert-manager"

echo "=== Installing cert-manager ${CERT_MANAGER_VERSION} (Gateway API support: ${ENABLE_GATEWAY_API}) ==="
# config.enableGatewayAPI is the CURRENT flag (cert-manager >= 1.15); the old
# --feature-gates=ExperimentalGatewayAPISupport was removed. crds.enabled
# installs cert-manager's own CRDs. When enableGatewayAPI=true the controller
# ALSO needs the Gateway API CRDs already present in the cluster (it crash-loops
# at startup otherwise); enableGatewayAPI=false drops that requirement entirely.
"${HELM[@]}" upgrade --install cert-manager "$CERT_MANAGER_CHART" \
    --version "${CERT_MANAGER_VERSION}" \
    --namespace cert-manager --create-namespace \
    --set crds.enabled=true \
    --set config.enableGatewayAPI="${ENABLE_GATEWAY_API}" \
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
