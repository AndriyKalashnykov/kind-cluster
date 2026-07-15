#!/usr/bin/env bash
# Install the NGINX Inc. (nginxinc/kubernetes-ingress) classic Ingress controller
# as an OPT-IN alternative to the default Traefik Ingress. This is the F5/NGINX
# commercially-maintained OSS edition — distinct from the community
# `kubernetes/ingress-nginx` that retired in March 2026. It registers
# IngressClass `nginx`, reconciles only Ingresses with `ingressClassName: nginx`,
# and its Service is type LoadBalancer — cloud-provider-kind gives it its OWN
# external IP, a distinct front door for the SAME demo apps.
#
# IngressClass `nginx` (networking.k8s.io) here is a DIFFERENT API object from
# GatewayClass `nginx` used by NGINX Gateway Fabric (`make gateway-nginx`) — they
# do not collide. A classic Ingress controller never watches GatewayClass, so the
# Gateway API v1.5.1 `supportedFeatures` crash does not apply. The chart installs
# its own k8s.nginx.org CRDs (VirtualServer/Policy/etc.), unrelated to Gateway API.
# See docs/gateway-api-ingress.md.
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

# renovate: datasource=docker depName=ghcr.io/nginx/charts/nginx-ingress
NGINX_INGRESS_VERSION=2.6.2
NGINX_INGRESS_CHART="oci://ghcr.io/nginx/charts/nginx-ingress"

echo "=== Installing NGINX Inc. Ingress controller (OSS, chart ${NGINX_INGRESS_VERSION}) ==="
# nginxplus defaults to false (OSS edition). service.type defaults to
# LoadBalancer; set it explicitly for clarity. setAsDefaultIngress=false avoids
# colliding with Traefik's default class. The chart installs its own CRDs.
"${HELM[@]}" upgrade --install nginx "$NGINX_INGRESS_CHART" \
    --version "${NGINX_INGRESS_VERSION}" \
    --namespace nginx-ingress --create-namespace \
    --set controller.ingressClass.name=nginx \
    --set controller.ingressClass.setAsDefaultIngress=false \
    --set controller.service.type=LoadBalancer \
    --wait --timeout "${TIMEOUT}"
"${KUBECTL[@]}" -n nginx-ingress rollout status deployment/nginx-nginx-ingress-controller --timeout="${TIMEOUT}"

echo "=== Applying the NGINX Ingress for the demo apps (ingressClassName: nginx) ==="
"${KUBECTL[@]}" apply -f k8s/demo-apps-ingress-nginx.yaml

# Discover the controller's LoadBalancer Service by type (its name is
# <release>-nginx-ingress-controller; selecting by type is robust).
NGINX_SVC=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
  NGINX_SVC=$("${KUBECTL[@]}" -n nginx-ingress get svc \
    -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -1 || echo "")
  [ -n "$NGINX_SVC" ] && break
  sleep "${POLL_INTERVAL:-2}"
done

echo "NGINX Inc. Ingress installed. Its controller Service ($NGINX_SVC) gets its own LoadBalancer IP:"
[ -n "$NGINX_SVC" ] && "${KUBECTL[@]}" -n nginx-ingress get svc "$NGINX_SVC" \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true
echo ""
echo "Reach the same demo apps via NGINX Inc., e.g.:"
echo "  SVC=\$(kubectl -n nginx-ingress get svc -o jsonpath='{range .items[?(@.spec.type==\"LoadBalancer\")]}{.metadata.name}{end}')"
echo "  IP=\$(kubectl -n nginx-ingress get svc \$SVC -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
echo "  curl -H 'Host: helloweb.localdev.me' http://\$IP/"
