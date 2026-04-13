#!/bin/bash
# Install Kubernetes Dashboard (Helm chart v7.x) + admin ServiceAccount.
#
# Dashboard v7 deploys multiple components (kong, api, web, auth, metrics-scraper);
# access goes through the Kong proxy. See: https://github.com/kubernetes/dashboard
#
# Usage: kind-add-dashboard.sh [CHART_VERSION]
# Default CHART_VERSION is pinned below. Renovate tracks updates via the comment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# renovate: datasource=github-releases depName=kubernetes/dashboard extractVersion=^kubernetes-dashboard-(?<version>.+)$
DASHBOARD_CHART_VERSION=7.14.0

VERSION=${1:-$DASHBOARD_CHART_VERSION}

# Clean up any stale cluster-scoped resources from previous v2 installs.
kubectl delete clusterrolebinding --ignore-not-found=true kubernetes-dashboard
kubectl delete clusterrole --ignore-not-found=true kubernetes-dashboard

CHART_TGZ_URL="https://github.com/kubernetes/dashboard/releases/download/kubernetes-dashboard-${VERSION}/kubernetes-dashboard-${VERSION}.tgz"
helm upgrade --install kubernetes-dashboard "$CHART_TGZ_URL" \
    --create-namespace --namespace kubernetes-dashboard \
    --wait --timeout 5m

kubectl apply -n kubernetes-dashboard -f ./k8s/dashboard-admin.yaml

# Wait for the auto-populated ServiceAccountToken Secret.
for _ in $(seq 1 30); do
    if kubectl get secret -n kubernetes-dashboard admin-user-token \
         -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then
        break
    fi
    sleep 1
done

dashboard_admin_token=$(kubectl get secret -n kubernetes-dashboard admin-user-token \
    -o jsonpath="{.data.token}" | base64 --decode)
echo "${dashboard_admin_token}" > dashboard-admin-token.txt
kubectl config set-credentials cluster-admin --token="${dashboard_admin_token}"

echo
echo "Dashboard installed (chart v${VERSION})."
echo "Admin token written to: dashboard-admin-token.txt"
echo "Forward the UI with: make dashboard-forward"