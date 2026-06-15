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


# Image pin — kept in sync with k8s/foo-bar-deployment.yaml via Renovate's
# docker-image grouping rule in renovate.json.
# renovate: datasource=docker depName=hashicorp/http-echo
HTTP_ECHO_VERSION=1.0.0
IMAGE=hashicorp/http-echo:${HTTP_ECHO_VERSION}

# Load the image as a single-platform archive — avoids kind#3795 where a
# multi-arch manifest list in Docker's containerd image store breaks
# `kind load docker-image` (ctr: content digest not found). See lib.sh.
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"
kind_load_image "$IMAGE" "$KIND_CLUSTER_NAME"

echo "deploying foo-bar-service"
"${KUBECTL[@]}" apply -f ./k8s/foo-bar-deployment.yaml

echo "waiting for foo-bar-service pods"
"${KUBECTL[@]}" wait pods -n default -l app=http-echo --for condition=Ready --timeout="${TIMEOUT}"
# Service is ClusterIP — exposed via ingress at http://foo.localdev.me/
# (load-balances across foo-app and bar-app Deployments via the shared
# `app: http-echo` selector). Ingress resource: k8s/demo-apps-ingress.yaml.

