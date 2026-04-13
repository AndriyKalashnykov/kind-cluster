#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# Force single-platform pull — avoids kind#3795 where a multi-arch manifest list
# in docker's content store breaks `kind load docker-image` (ctr: content digest not found).
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
docker pull --platform="$PLATFORM" hashicorp/http-echo:0.2.3
kind load docker-image hashicorp/http-echo:0.2.3

echo "deploying foo-bar-service"
kubectl apply -f ./k8s/foo-bar-deployment.yaml

echo "waiting for foo-bar-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout="${TIMEOUT}"

echo "waiting for foo-bar-service service to get External-IP"
for _ in $(seq 1 90); do
    kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: foo-service did not get an External-IP after 180s"; kubectl get svc foo-service; exit 1; }

LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

# MetalLB IPs are on the Docker bridge network and not routable from the host;
# curl from INSIDE the kind control-plane node instead (same bridge).
KIND_NODE=$(docker ps --filter label=io.x-k8s.kind.role=control-plane --format '{{.Names}}' | head -1)
for _ in {1..10}; do
  docker exec "${KIND_NODE}" curl -s --max-time 10 "http://${LB_IP}:5678" \
    || echo "  (curl http://${LB_IP}:5678 via ${KIND_NODE} failed)"
done

