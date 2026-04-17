#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# Image pin — kept in sync with k8s/helloweb-deployment.yaml via Renovate's
# docker-image grouping rule in renovate.json.
# renovate: datasource=docker depName=us-docker.pkg.dev/google-samples/containers/gke/hello-app
HELLO_APP_VERSION=1.0
IMAGE=us-docker.pkg.dev/google-samples/containers/gke/hello-app:${HELLO_APP_VERSION}

# Force single-platform pull — avoids kind#3795 where a multi-arch manifest list
# in docker's content store breaks `kind load docker-image` (ctr: content digest not found).
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
docker pull --platform="$PLATFORM" "$IMAGE"
kind load docker-image "$IMAGE"

echo "deploying helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml

echo "waiting for helloweb pods"
kubectl wait deployment -n default helloweb --for condition=Available=True --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed to the host through ingress-nginx via the
# demo-apps Ingress (k8s/demo-apps-ingress.yaml, applied by kind-install-all.sh).
# Reach it at http://helloweb.localdev.me/ after adding the host to /etc/hosts.

