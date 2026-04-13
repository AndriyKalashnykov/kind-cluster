#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1


# https://computingforgeeks.com/how-to-deploy-metrics-server-to-kubernetes-cluster/

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install --set 'args={--kubelet-insecure-tls}' metrics-server metrics-server/metrics-server --namespace kube-system

kubectl rollout status deployment/metrics-server -n kube-system --timeout=3m
kubectl get deploy,svc -n kube-system | grep -E metrics-server
# APIService can take ~30s after rollout before it accepts queries; retry.
for _ in 1 2 3 4 5 6 7 8 9 10; do
    kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes" >/dev/null 2>&1 && { echo "metrics API ready"; break; }
    sleep 3
done

