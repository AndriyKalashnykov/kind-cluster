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
"${KUBECTL[@]}" apply -f ./k8s/helloweb-deployment.yaml

echo "waiting for helloweb pods"
"${KUBECTL[@]}" wait deployment -n default helloweb --for condition=Available=True --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed to the host through ingress-nginx via the
# demo-apps Ingress (k8s/demo-apps-ingress.yaml, applied by kind-install-all.sh).
# Reach it at http://helloweb.localdev.me/ after adding the host to /etc/hosts.

