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
docker pull --platform="$PLATFORM" us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0
kind load docker-image us-docker.pkg.dev/google-samples/containers/gke/hello-app:1.0

echo "deploying helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml

echo "waiting for helloweb pods"
kubectl wait deployment -n default helloweb --for condition=Available=True --timeout="${TIMEOUT}"

# https://stackoverflow.com/questions/70108499/kubectl-wait-for-service-on-aws-eks-to-expose-elastic-load-balancer-elb-addres/70108500#70108500
echo "waiting for helloweb service to get External-IP"
for _ in $(seq 1 90); do
    kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: helloweb did not get an External-IP after 180s"; kubectl get svc helloweb; exit 1; }

service_ip=$(kubectl get services helloweb -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
# MetalLB IPs are only reachable from inside the kind Docker bridge network.
KIND_NODE=$(docker ps --filter label=io.x-k8s.kind.role=control-plane --format '{{.Names}}' | head -1)
docker exec "${KIND_NODE}" curl -s --max-time 10 "http://${service_ip}:80" \
  || echo "(curl http://${service_ip}:80 via ${KIND_NODE} failed)"

