#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# https://github.com/kubernetes/ingress-nginx
# Pin to a release tag instead of `main` — branch-pinning silently pulls
# whatever is on main at install time (untrackable by Renovate, drift risk).
# The existing scripts/*.sh custom.regex manager in renovate.json tracks this.
# renovate: datasource=github-releases depName=kubernetes/ingress-nginx
INGRESS_NGINX_VERSION=controller-v1.15.1

echo "deploying nginx ingress for kind ${INGRESS_NGINX_VERSION}"
"${KUBECTL[@]}" apply -f "https://raw.githubusercontent.com/kubernetes/ingress-nginx/${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

# Pin the controller to the kind-control-plane node: only that node has the
# `ingress-ready=true` label and the extraPortMappings 80/443 configured in
# k8s/kind-config.yaml. Without this, the scheduler may place the pod on
# kind-worker, leaving host:80 with nothing to forward to via hostPort.
echo "pinning ingress-nginx controller to nodes labelled ingress-ready=true"
"${KUBECTL[@]}" -n ingress-nginx patch deployment ingress-nginx-controller --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'

echo "waiting for nginx"
"${KUBECTL[@]}" -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout="${TIMEOUT}"
"${KUBECTL[@]}" wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout="${TIMEOUT}"

