#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

echo "deploy golang-hello-world-web"
# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
kubectl apply -f https://raw.githubusercontent.com/fabianlee/k3s-cluster-kvm/main/roles/golang-hello-world-web/templates/golang-hello-world-web.yaml.j2
echo "wait for golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout=180s

cd $LAUNCH_DIR