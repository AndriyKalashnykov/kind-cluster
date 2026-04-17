#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# Image pin — kept in sync with k8s/golang-hello-world-web.yaml via Renovate's
# docker-image grouping rule in renovate.json.
# renovate: datasource=docker depName=ghcr.io/andriykalashnykov/golang-web
GOLANG_WEB_VERSION=0.0.3
IMAGE=ghcr.io/andriykalashnykov/golang-web:${GOLANG_WEB_VERSION}

# Force single-platform pull — avoids kind#3795 where a multi-arch manifest list
# in docker's content store breaks `kind load docker-image` (ctr: content digest not found).
PLATFORM="linux/$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
docker pull --platform="$PLATFORM" "$IMAGE"
kind load docker-image "$IMAGE"

echo "deploying golang-hello-world-web"
kubectl apply -f ./k8s/golang-hello-world-web.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout="${TIMEOUT}"

echo "waiting for golang-hello-world-web service to get External-IP"
for _ in $(seq 1 90); do
    kubectl get service/golang-hello-world-web-service -n default --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
kubectl get service/golang-hello-world-web-service -n default --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: golang-hello-world-web-service did not get an External-IP after 180s"; kubectl get svc golang-hello-world-web-service; exit 1; }

service_ip=$(kubectl get services golang-hello-world-web-service -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

# MetalLB IPs are only reachable from inside the kind Docker bridge network.
KIND_NODE=$(docker ps --filter label=io.x-k8s.kind.role=control-plane --format '{{.Names}}' | head -1)
docker exec "${KIND_NODE}" curl -s --max-time 10 "http://${service_ip}:8080/myhello/" \
  || echo "(curl http://${service_ip}:8080/myhello/ via ${KIND_NODE} failed)"
docker exec "${KIND_NODE}" curl -s --max-time 10 "http://${service_ip}:8080/healthz" \
  || echo "(curl http://${service_ip}:8080/healthz via ${KIND_NODE} failed)"

