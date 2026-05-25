#!/bin/bash
# Port-forward the Headlamp UI to http://localhost:8081.
# Prints the admin token and (optionally) opens a browser.
#
# Usage: kind-forward-headlamp.sh [LOCAL_PORT]
# Default LOCAL_PORT is 8081 (8080 is reserved for the deploy-app demos).

set -euo pipefail

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

LOCAL_PORT=${1:-8081}
NS=headlamp
SVC=headlamp

if ! "${KUBECTL[@]}" get svc "$SVC" -n "$NS" >/dev/null 2>&1; then
    echo "Error: service $SVC not found in namespace $NS."
    echo "Run: make headlamp-install"
    exit 1
fi

if [ -f headlamp-admin-token.txt ]; then
    echo
    echo "=== Headlamp admin token (paste into the login screen) ==="
    cat headlamp-admin-token.txt
    echo
    echo "=========================================================="
    echo
fi

echo "Opening http://localhost:${LOCAL_PORT} (Ctrl+C to stop forwarding)"
if command -v xdg-open >/dev/null 2>&1; then
    (sleep 2 && xdg-open "http://localhost:${LOCAL_PORT}") &
elif command -v open >/dev/null 2>&1; then
    (sleep 2 && open "http://localhost:${LOCAL_PORT}") &
fi

"${KUBECTL[@]}" -n "$NS" port-forward "svc/${SVC}" "${LOCAL_PORT}:80"
