#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

echo "deploy foo-bar-service"
kubectl apply -f ./k8s/foo-bar-deployment.yaml
echo "wait for foo-bar-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout=180s
echo "wait for foo-bar-service service to get External-IP"
until kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in {1..10}; do
  curl -s ${LB_IP}:5678
done

cd $LAUNCH_DIR