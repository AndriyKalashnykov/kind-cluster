#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# https://github.com/kubernetes/ingress-nginx

echo "deploying nginx ingress for kind"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# Pin the controller to the kind-control-plane node: only that node has the
# `ingress-ready=true` label and the extraPortMappings 80/443 configured in
# k8s/kind-config.yaml. Without this, the scheduler may place the pod on
# kind-worker, leaving host:80 with nothing to forward to via hostPort.
echo "pinning ingress-nginx controller to nodes labelled ingress-ready=true"
kubectl -n ingress-nginx patch deployment ingress-nginx-controller --type=strategic \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true"}}}}}'

echo "waiting for nginx"
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout="${TIMEOUT}"
kubectl wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout="${TIMEOUT}"

