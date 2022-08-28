#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# https://computingforgeeks.com/how-to-deploy-metrics-server-to-kubernetes-cluster/

helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo update
helm upgrade --install --set args={--kubelet-insecure-tls} metrics-server metrics-server/metrics-server --namespace kube-system

kubectl get deploy,svc -n kube-system | egrep metrics-server
kubectl get --raw "/apis/metrics.k8s.io/v1beta1/nodes"

cd $LAUNCH_DIR