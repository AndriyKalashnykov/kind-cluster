#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# Image pin — kept in sync with k8s/golang-hello-world-web.yaml via Renovate's
# docker-image grouping rule in renovate.json.
# renovate: datasource=docker depName=ghcr.io/andriykalashnykov/golang-web
GOLANG_WEB_VERSION=0.0.3
IMAGE=ghcr.io/andriykalashnykov/golang-web:${GOLANG_WEB_VERSION}

# Force single-platform pull — avoids kind#3795 where a multi-arch manifest list
# in docker's content store breaks `kind load docker-image` (ctr: content digest not found).
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
docker pull --platform="$PLATFORM" "$IMAGE"
kind load docker-image "$IMAGE"

echo "deploying golang-hello-world-web"
kubectl apply -f ./k8s/golang-hello-world-web.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed via ingress at http://golang.localdev.me/myhello/
# and /healthz. The ingress resource lives in k8s/demo-apps-ingress.yaml.

