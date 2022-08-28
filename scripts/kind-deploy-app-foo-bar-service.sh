#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

echo "deploying foo-bar-service"
kubectl apply -f ./k8s/foo-bar-deployment.yaml

echo "waiting for foo-bar-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout=${TIMEOUT}

echo "waiting for foo-bar-service service to get External-IP"
until kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')

for _ in {1..10}; do
  curl -s ${LB_IP}:5678
done

cd $LAUNCH_DIR