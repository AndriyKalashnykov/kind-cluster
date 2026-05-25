#!/bin/bash
# Install Headlamp (kubernetes-sigs/headlamp) + admin ServiceAccount.
#
# Headlamp is the SIG-UI-endorsed Kubernetes web UI; the original
# kubernetes/dashboard project was archived 2026-01-21 with Headlamp as
# the recommended replacement. See: https://github.com/kubernetes-sigs/headlamp
#
# Single-pod ClusterIP deployment on port 80 (HTTP). Token-based login —
# paste the admin token from `headlamp-admin-token.txt` (or
# `make headlamp-token`) into the UI.
#
# Usage: kind-add-headlamp.sh [CHART_VERSION]
# Default CHART_VERSION is pinned below. Renovate tracks updates via the comment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

# renovate: datasource=helm depName=headlamp registryUrl=https://kubernetes-sigs.github.io/headlamp/
HEADLAMP_CHART_VERSION=0.42.0

VERSION=${1:-$HEADLAMP_CHART_VERSION}

# Install the chart from the per-release GitHub-released tarball directly —
# avoids the `helm repo add`+index.yaml stale-redirect class of failure.
# Renovate-tracked via the comment above HEADLAMP_CHART_VERSION.
CHART_URL="https://github.com/kubernetes-sigs/headlamp/releases/download/headlamp-helm-${VERSION}/headlamp-${VERSION}.tgz"

helm upgrade --install headlamp "$CHART_URL" \
    --create-namespace --namespace headlamp \
    --wait --timeout 5m

"${KUBECTL[@]}" apply -n headlamp -f ./k8s/headlamp-admin.yaml

# Wait for the auto-populated ServiceAccountToken Secret.
for _ in $(seq 1 30); do
    if "${KUBECTL[@]}" get secret -n headlamp admin-user-token \
         -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then
        break
    fi
    sleep 1
done

headlamp_admin_token=$("${KUBECTL[@]}" get secret -n headlamp admin-user-token \
    -o jsonpath="{.data.token}" | base64 --decode)
echo "${headlamp_admin_token}" > headlamp-admin-token.txt
"${KUBECTL[@]}" config set-credentials cluster-admin --token="${headlamp_admin_token}"

echo
echo "Headlamp installed (chart v${VERSION})."
echo "Admin token written to: headlamp-admin-token.txt"
echo "Forward the UI with: make headlamp-forward"
