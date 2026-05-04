#!/bin/bash
# Print the Kubernetes Dashboard admin-user token.
# Prefers the long-lived Secret created by k8s/dashboard-admin.yaml;
# falls back to a short-lived token via `kubectl create token`.

set -euo pipefail

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

NS=kubernetes-dashboard
SA=admin-user
SECRET=admin-user-token

if "${KUBECTL[@]}" get secret "$SECRET" -n "$NS" >/dev/null 2>&1; then
    "${KUBECTL[@]}" get secret -n "$NS" "$SECRET" \
        -o jsonpath="{.data.token}" | base64 --decode
    echo
else
    echo "No long-lived Secret found; generating ephemeral token..." >&2
    "${KUBECTL[@]}" -n "$NS" create token "$SA"
fi
