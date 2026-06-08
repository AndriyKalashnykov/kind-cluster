#!/usr/bin/env bash
# Install Project Contour (Gateway provisioner) as a Gateway API controller that
# coexists with Traefik, Istio and NGINX Gateway Fabric, fronting the SAME demo
# apps via its own LoadBalancer IP. Contour is NOT a CNI — it installs over the
# existing kindnet cluster.
#
# We use Contour's "Gateway provisioner" (dynamic), NOT the static install: the
# static Envoy DaemonSet binds host ports 80/443 and would collide with Traefik
# on the control-plane node. The provisioner instead creates a per-Gateway
# Contour+Envoy with a type=LoadBalancer Envoy Service, so cloud-provider-kind
# gives it its own external IP — the same clean-coexistence model as Istio/NGF.
#
# CRITICAL: Contour's all-in-one provisioner render BUNDLES the upstream Gateway
# API CRDs (experimental channel). Applying them would clobber/downgrade the
# shared standard-channel v1.5.1 CRDs that Traefik/Istio/NGF rely on (and the
# v1.5 safe-upgrades admission policy would reject a downgrade). So we strip the
# bundled gateway.networking.k8s.io CRD documents and reuse the shared ones.
# Contour 1.33 conforms to Gateway API v1.3, which is wire-compatible with the
# v1.5.1 standard v1 resources via the Gateway API v1 backward-compatibility
# guarantee (additive-only within the v1 major).
#
# Requires `make install-all` first (cloud-provider-kind must be running so the
# provisioned Envoy Service gets an external IP).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# renovate: datasource=docker depName=ghcr.io/projectcontour/contour
CONTOUR_VERSION=v1.33.5
CONTOUR_MANIFEST="https://raw.githubusercontent.com/projectcontour/contour/${CONTOUR_VERSION}/examples/render/contour-gateway-provisioner.yaml"

# Shared Gateway API CRDs first (idempotent, standard channel v1.5.1).
"$SCRIPT_DIR/kind-add-gateway-api-crds.sh"

echo "=== Installing Contour Gateway provisioner ${CONTOUR_VERSION} (bundled Gateway API CRDs stripped) ==="
# Drop every `gateway.networking.k8s.io` CustomResourceDefinition document so we
# do NOT overwrite the shared standard-channel CRDs; apply the rest (provisioner
# Deployment, RBAC, Namespace, Contour's own projectcontour.io CRDs). The awk
# buffers each `---`-separated document and prints it unless it is a Gateway API
# CRD — dependency-free (no yq/python) so it runs identically in CI.
curl -fsSL "$CONTOUR_MANIFEST" | awk '
  function flush() {
    if (buf != "") {
      if (!(buf ~ /kind: CustomResourceDefinition/ && buf ~ /name: [a-z.]+\.gateway\.networking\.k8s\.io/)) {
        printf "%s", buf; print "---"
      }
    }
    buf=""
  }
  /^---[[:space:]]*$/ { flush(); next }
  { buf = buf $0 "\n" }
  END { flush() }
' | "${KUBECTL[@]}" apply -f -

"${KUBECTL[@]}" -n projectcontour rollout status deployment/contour-gateway-provisioner --timeout="${TIMEOUT}"

echo "=== Applying Contour GatewayClass + Gateway + HTTPRoutes (provisions per-Gateway Envoy) ==="
"${KUBECTL[@]}" apply -f k8s/gateway/contour-gateway.yaml
# The provisioner reconciles GatewayClass `contour` and provisions a Contour +
# Envoy data plane in the Gateway's namespace. For Gateway `contour` in default,
# the Envoy Service is `envoy-contour` (type LoadBalancer) and the data plane is
# an `envoy-contour` DaemonSet. Provisioning is async — wait for the Service to
# appear, then for the DaemonSet rollout.
for _ in $(seq 1 60); do
  "${KUBECTL[@]}" -n default get svc/envoy-contour >/dev/null 2>&1 && break
  sleep 2
done
"${KUBECTL[@]}" -n default rollout status daemonset/envoy-contour --timeout="${TIMEOUT}"

echo "Contour installed. Its Envoy Service gets its own LoadBalancer IP:"
"${KUBECTL[@]}" -n default get svc envoy-contour \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via Contour, e.g.:"
echo "  IP=\$(kubectl -n default get svc envoy-contour -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
