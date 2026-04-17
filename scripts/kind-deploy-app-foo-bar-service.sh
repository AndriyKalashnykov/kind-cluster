#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# Image pin — kept in sync with k8s/foo-bar-deployment.yaml via Renovate's
# docker-image grouping rule in renovate.json.
# renovate: datasource=docker depName=hashicorp/http-echo
HTTP_ECHO_VERSION=1.0.0
IMAGE=hashicorp/http-echo:${HTTP_ECHO_VERSION}

# Force single-platform pull — avoids kind#3795 where a multi-arch manifest list
# in docker's content store breaks `kind load docker-image` (ctr: content digest not found).
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
docker pull --platform="$PLATFORM" "$IMAGE"
kind load docker-image "$IMAGE"

echo "deploying foo-bar-service"
kubectl apply -f ./k8s/foo-bar-deployment.yaml

echo "waiting for foo-bar-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed via ingress at http://foo.localdev.me/
# (load-balances across foo-app and bar-app Deployments via the shared
# `app: http-echo` selector). Ingress resource: k8s/demo-apps-ingress.yaml.

