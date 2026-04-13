#!/bin/bash
# Smoke-test the local registry created by kind-with-registry.sh:
#   1. pull a public image
#   2. retag and push to localhost:5001
#   3. deploy a manifest that references the locally-pushed image
#   4. curl the service to prove it serves
#
# Usage: test-registry.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app
docker pull gcr.io/google-samples/hello-app:1.0
docker tag gcr.io/google-samples/hello-app:1.0 localhost:5001/hello-app:1.0
docker push localhost:5001/hello-app:1.0
kubectl apply -f ./k8s/helloweb-deployment-local.yaml
kubectl rollout status deployment/helloweb --timeout=60s
kubectl port-forward svc/helloweb 8080:80 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
sleep 2
curl -sf http://localhost:8080
