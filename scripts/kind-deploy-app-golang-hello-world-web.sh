#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

echo "deploy golang-hello-world-web"
kubectl apply -f ./k8s/golang-hello-world-web.yaml
# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "wait for golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout=180s

service_ip=$(kubectl get services golang-hello-world-web-service -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

curl -s ${service_ip}:8080/myhello/

cd $LAUNCH_DIR