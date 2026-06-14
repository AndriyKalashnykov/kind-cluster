#!/usr/bin/env bash
# Install the HAProxy (haproxytech/kubernetes-ingress) classic Ingress controller
# as an OPT-IN alternative to the default Traefik Ingress. It registers
# IngressClass `haproxy`, so it reconciles only Ingresses with
# `ingressClassName: haproxy` (it ignores Traefik's, and vice versa), and its
# proxy Service is type LoadBalancer — cloud-provider-kind gives it its OWN
# external IP, a distinct front door for the SAME demo apps.
#
# This is the OFFICIAL HAProxy Technologies controller, distinct from the
# community `jcmoraisjr/haproxy-ingress` that this project dropped from Gateway
# API mode. As a CLASSIC Ingress controller it never watches GatewayClass, so
# the Gateway API v1.5.1 `supportedFeatures` crash does not apply; it gracefully
# logs one warning about the unrecognised GW API CRD version and serves Ingress
# normally. See docs/gateway-api-ingress.md.
#
# Requires `make install-all` first (cloud-provider-kind must be running so the
# controller Service gets an external IP) and the demo apps deployed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")
HELM=(helm --kube-context="kind-${KIND_CLUSTER_NAME}")
TIMEOUT="${1:-5m}"

# renovate: datasource=helm depName=kubernetes-ingress registryUrl=https://haproxytech.github.io/helm-charts
HAPROXY_INGRESS_VERSION=1.52.0
HAPROXY_INGRESS_REPO=https://haproxytech.github.io/helm-charts

echo "=== Installing HAProxy Ingress controller (chart ${HAPROXY_INGRESS_VERSION}) ==="
# --wait blocks until the controller Deployment (and the chart's CRD-install
# Helm hook for haproxytech's own *.ingress.v3.haproxy.org CRDs) is ready. The
# service is NodePort by default — override to LoadBalancer so it gets an IP.
# ingressClassResource.default=false avoids colliding with Traefik's default class.
"${HELM[@]}" upgrade --install haproxytech kubernetes-ingress \
    --repo "$HAPROXY_INGRESS_REPO" --version "${HAPROXY_INGRESS_VERSION}" \
    --namespace haproxy-controller --create-namespace \
    --set controller.service.type=LoadBalancer \
    --set controller.ingressClassResource.name=haproxy \
    --set controller.ingressClass=haproxy \
    --set controller.ingressClassResource.default=false \
    --wait --timeout "${TIMEOUT}"
"${KUBECTL[@]}" -n haproxy-controller rollout status deployment/haproxytech-kubernetes-ingress --timeout="${TIMEOUT}"

echo "=== Applying the HAProxy Ingress for the demo apps (ingressClassName: haproxy) ==="
"${KUBECTL[@]}" apply -f k8s/demo-apps-ingress-haproxy.yaml

# Discover the controller's LoadBalancer Service by type (its name is
# <release>-kubernetes-ingress = haproxytech-kubernetes-ingress; selecting by
# type is robust to release-name changes).
HAPROXY_SVC=""
for _ in $(seq 1 30); do
  HAPROXY_SVC=$("${KUBECTL[@]}" -n haproxy-controller get svc \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "")
  [ -n "$HAPROXY_SVC" ] && break
  sleep 2
done

echo "HAProxy Ingress installed. Its controller Service ($HAPROXY_SVC) gets its own LoadBalancer IP:"
[ -n "$HAPROXY_SVC" ] && "${KUBECTL[@]}" -n haproxy-controller get svc "$HAPROXY_SVC" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via HAProxy, e.g.:"
echo "  SVC=\$(kubectl -n haproxy-controller get svc -o jsonpath='{range .items[?(@.spec.type==\"LoadBalancer\")]}{.metadata.name}{end}')"
echo "  IP=\$(kubectl -n haproxy-controller get svc \$SVC -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
