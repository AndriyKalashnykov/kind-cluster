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


# https://computingforgeeks.com/how-to-deploy-metrics-server-to-kubernetes-cluster/

# Chart version pinned (was floating on `latest`). Renovate's scripts
# custom.regex manager bumps it via the inline comment below.
# renovate: datasource=helm depName=metrics-server registryUrl=https://kubernetes-sigs.github.io/metrics-server/
METRICS_SERVER_CHART_VERSION=3.13.0

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install --set 'args={--kubelet-insecure-tls}' \
  --version "${METRICS_SERVER_CHART_VERSION}" \
  metrics-server metrics-server/metrics-server --namespace kube-system

"${KUBECTL[@]}" rollout status deployment/metrics-server -n kube-system --timeout=3m
"${KUBECTL[@]}" get deploy,svc -n kube-system | grep -E metrics-server
# APIService can take ~30s after rollout before it accepts queries; retry.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    "${KUBECTL[@]}" get --raw "/apis/metrics.k8s.io/v1beta1/nodes" >/dev/null 2>&1 && { echo "metrics API ready"; break; }
    sleep 3
done

