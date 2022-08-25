#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

echo "deploy helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml
echo "wait for deploy helloweb pods"
kubectl wait deployment -n default helloweb --for condition=Available=True --timeout=180s
# https://stackoverflow.com/questions/70108499/kubectl-wait-for-service-on-aws-eks-to-expose-elastic-load-balancer-elb-addres/70108500#70108500
echo "wait for helloweb service to get External-IP"
until kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
kubectl get services helloweb -n default -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}"
service_ip=$(kubectl get services helloweb -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")

curl -s ${service_ip}:80

cd $LAUNCH_DIR