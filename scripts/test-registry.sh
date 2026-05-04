#!/bin/bash
# Smoke-test the local registry created by kind-with-registry.sh:
#   1. pull a public image
#   2. retag and push to localhost:5001
#   3. deploy a manifest that references the locally-pushed image
#   4. curl the service to prove it serves
#
# Usage: test-registry.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Pinned to the registry-wired cluster (created by kind-with-registry.sh,
# default name `kind-registry`). Distinct from the default `kind` cluster
# used by `make install-all`. Use an explicit context so a parallel
# `make` invocation in another KinD project can't silently switch us
# to a different cluster mid-script.
CLUSTER_NAME="${CLUSTER_NAME:-kind-registry}"
KUBECTL=(kubectl --context="kind-${CLUSTER_NAME}")

# https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app
# Renovate tracks this via the inline comment; `k8s/helloweb-deployment-local.yaml`
# has a matching `localhost:5001/hello-app:<tag>` reference that must be kept in
# sync by hand (Renovate can't reach `localhost:5001` to propose bumps there).
# renovate: datasource=docker depName=gcr.io/google-samples/hello-app
HELLO_APP_VERSION=2.0
UPSTREAM=gcr.io/google-samples/hello-app:${HELLO_APP_VERSION}
LOCAL=localhost:5001/hello-app:${HELLO_APP_VERSION}

docker pull "$UPSTREAM"
docker tag "$UPSTREAM" "$LOCAL"
docker push "$LOCAL"
"${KUBECTL[@]}" apply -f ./k8s/helloweb-deployment-local.yaml
"${KUBECTL[@]}" rollout status deployment/helloweb --timeout=60s
"${KUBECTL[@]}" port-forward svc/helloweb 8080:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
sleep 2
curl -sf http://localhost:8080
