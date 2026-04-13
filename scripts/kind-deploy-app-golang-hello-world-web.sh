#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

docker pull ghcr.io/andriykalashnykov/golang-web:v0.0.1
kind load docker-image ghcr.io/andriykalashnykov/golang-web:v0.0.1

echo "deploying golang-hello-world-web"
kubectl apply -f ./k8s/golang-hello-world-web.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout=${TIMEOUT}

echo "waiting for golang-hello-world-web service to get External-IP"
for i in $(seq 1 90); do
    kubectl get service/golang-hello-world-web-service -n default --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
kubectl get service/golang-hello-world-web-service -n default --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: golang-hello-world-web-service did not get an External-IP after 180s"; kubectl get svc golang-hello-world-web-service; exit 1; }

service_ip=$(kubectl get services golang-hello-world-web-service -n default -o jsonpath="{.status.loadloadBalancer.ingress[0].ip}")

curl -s ${service_ip}:8080/myhello/
curl -s ${service_ip}:8080/healthz

cd $LAUNCH_DIR