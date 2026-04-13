#!/bin/bash
# Print the Kubernetes Dashboard admin-user token.
# Prefers the long-lived Secret created by k8s/dashboard-admin.yaml;
# falls back to a short-lived token via `kubectl create token`.

set -euo pipefail

NS=kubernetes-dashboard
SA=admin-user
SECRET=admin-user-token

if kubectl get secret "$SECRET" -n "$NS" >/dev/null 2>&1; then
    kubectl get secret -n "$NS" "$SECRET" \
        -o jsonpath="{.data.token}" | base64 --decode
    echo
else
    echo "No long-lived Secret found; generating ephemeral token..." >&2
    kubectl -n "$NS" create token "$SA"
fi
