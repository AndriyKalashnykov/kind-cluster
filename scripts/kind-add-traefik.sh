#!/bin/bash
# Install Traefik as the project's Ingress controller — replaces ingress-nginx,
# which entered retirement (best-effort maintenance ends March 2026) per its
# own README: https://www.kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/.
#
# Traefik 3.x supports both `networking.k8s.io/v1` Ingress (the project's
# existing manifest shape) and Gateway API, so the swap is drop-in for
# ingressClassName: traefik without rewriting demo-apps as Gateway routes.
#
# Pinned to the control-plane node (via nodeSelector ingress-ready=true +
# tolerations) so it occupies the same node as kind-config.yaml's
# extraPortMappings (containerPort 80/443 -> hostPort 80/443). Web/websecure
# entrypoints use hostPort so curl http://localhost/ reaches Traefik directly
# through that mapping — identical UX to the previous ingress-nginx setup.
#
# Usage: kind-add-traefik.sh [CHART_VERSION]
# Default CHART_VERSION is pinned below. Renovate tracks updates via the comment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

TIMEOUT=${1:-5m}

# renovate: datasource=helm depName=traefik registryUrl=https://traefik.github.io/charts
TRAEFIK_CHART_VERSION=41.0.0

VERSION=${2:-$TRAEFIK_CHART_VERSION}

# Direct chart tarball URL — bypasses `helm repo add`+index.yaml so upstream
# index restructures can't break the install silently. The Traefik chart
# isn't published as a GH release asset; the canonical static URL lives at
# https://traefik.github.io/charts/traefik/traefik-<VER>.tgz.
CHART_URL="https://traefik.github.io/charts/traefik/traefik-${VERSION}.tgz"

echo "deploying Traefik chart v${VERSION}"
helm --kube-context="kind-${KIND_CLUSTER_NAME}" upgrade --install traefik "$CHART_URL" \
    --create-namespace --namespace traefik \
    --set 'ports.web.hostPort=80' \
    --set 'ports.websecure.hostPort=443' \
    --set 'updateStrategy.type=Recreate' \
    --set-string 'nodeSelector.ingress-ready=true' \
    --set 'tolerations[0].key=node-role.kubernetes.io/control-plane' \
    --set 'tolerations[0].operator=Exists' \
    --set 'tolerations[0].effect=NoSchedule' \
    --wait --timeout "${TIMEOUT}"

echo "waiting for Traefik controller"
"${KUBECTL[@]}" -n traefik rollout status deployment/traefik --timeout="${TIMEOUT}"
"${KUBECTL[@]}" wait pods -n traefik -l app.kubernetes.io/name=traefik --for condition=Ready --timeout="${TIMEOUT}"
