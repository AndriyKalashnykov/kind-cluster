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
"${KUBECTL[@]}" apply -f ./k8s/golang-hello-world-web.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for golang-hello-world-web pods"
"${KUBECTL[@]}" wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed via ingress at http://golang.localdev.me/myhello/
# and /healthz. The ingress resource lives in k8s/demo-apps-ingress.yaml.

