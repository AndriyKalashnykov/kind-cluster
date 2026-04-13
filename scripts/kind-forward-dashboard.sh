#!/bin/bash
# Port-forward the Kubernetes Dashboard Kong proxy to https://localhost:8443.
# Prints the admin token and (optionally) opens a browser.
#
# Usage: kind-forward-dashboard.sh [LOCAL_PORT]
# Default LOCAL_PORT is 8443.

set -euo pipefail

LOCAL_PORT=${1:-8443}
NS=kubernetes-dashboard
SVC=kubernetes-dashboard-kong-proxy

if ! kubectl get svc "$SVC" -n "$NS" >/dev/null 2>&1; then
    echo "Error: service $SVC not found in namespace $NS."
    echo "Run: make k8s-dashboard"
    exit 1
fi

if [ -f dashboard-admin-token.txt ]; then
    echo
    echo "=== Dashboard admin token ==="
    cat dashboard-admin-token.txt
    echo
    echo "============================"
    echo
fi

echo "Opening https://localhost:${LOCAL_PORT} (Ctrl+C to stop forwarding)"
if command -v xdg-open >/dev/null 2>&1; then
    (sleep 2 && xdg-open "https://localhost:${LOCAL_PORT}") &
elif command -v open >/dev/null 2>&1; then
    (sleep 2 && open "https://localhost:${LOCAL_PORT}") &
fi

kubectl -n "$NS" port-forward "svc/${SVC}" "${LOCAL_PORT}:443"
