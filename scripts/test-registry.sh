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
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

# Pinned to the registry-wired cluster (created by kind-with-registry.sh,
# default name `kind-registry`). Distinct from the default `kind` cluster
# used by `make install-all`. Use an explicit context so a parallel
# `make` invocation in another KinD project can't silently switch us
# to a different cluster mid-script.
CLUSTER_NAME="${CLUSTER_NAME:-kind-registry}"
KUBECTL=(kubectl --context="kind-${CLUSTER_NAME}")

# https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app
# This script is the single source of truth for the tag — Renovate updates
# HELLO_APP_VERSION via the inline comment below, and the tag is substituted
# into k8s/helloweb-deployment-local.yaml at apply time. The manifest's
# hardcoded tag is a fallback for direct `kubectl apply -f` use; the sed
# pipeline overrides it here so the two cannot drift.
# renovate: datasource=docker depName=gcr.io/google-samples/hello-app
HELLO_APP_VERSION=2.0
UPSTREAM=gcr.io/google-samples/hello-app:${HELLO_APP_VERSION}
LOCAL=localhost:5001/hello-app:${HELLO_APP_VERSION}

docker pull "$UPSTREAM"
docker tag "$UPSTREAM" "$LOCAL"
docker push "$LOCAL"
sed "s|localhost:5001/hello-app:[^[:space:]]*|${LOCAL}|" ./k8s/helloweb-deployment-local.yaml \
    | "${KUBECTL[@]}" apply -f -
"${KUBECTL[@]}" rollout status deployment/helloweb --timeout=60s

# Port-forward on an ephemeral local port — `:80` lets kubectl choose a free
# local port (avoids a collision when something else already holds :8080).
# Capture the chosen port from kubectl's "Forwarding from 127.0.0.1:<port>" line.
PF_LOG=$(mktemp)
"${KUBECTL[@]}" port-forward svc/helloweb :80 >"$PF_LOG" 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true; rm -f "$PF_LOG"' EXIT

LOCAL_PORT=""
for _ in $(seq 1 30); do
    LOCAL_PORT=$(pf_local_port "$(cat "$PF_LOG")")
    [ -n "$LOCAL_PORT" ] && break
    sleep 1
done
if [ -z "$LOCAL_PORT" ]; then
    echo "ERROR: kubectl port-forward did not report a local port within 30s"
    cat "$PF_LOG"
    exit 1
fi

# Body-assert: hello-app serves a distinctive "Hello, world!" line. A bare
# status check would pass even if the forward reached an unintended backend.
BODY=$(curl -sf --retry 5 --retry-connrefused --retry-delay 1 "http://localhost:${LOCAL_PORT}") \
    || { echo "ERROR: curl to helloweb (localhost:${LOCAL_PORT}) failed"; exit 1; }
echo "$BODY"
echo "$BODY" | grep -q 'Hello, world!' \
    || { echo "ERROR: helloweb response did not contain 'Hello, world!'"; exit 1; }
echo "registry-test: helloweb served the expected body via localhost:${LOCAL_PORT}"
