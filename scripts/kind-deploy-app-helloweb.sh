#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

echo "deploying helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml

echo "waiting for helloweb pods"
kubectl wait deployment -n default helloweb --for condition=Available=True --timeout=${TIMEOUT}

# https://stackoverflow.com/questions/70108499/kubectl-wait-for-service-on-aws-eks-to-expose-elastic-load-balancer-elb-addres/70108500#70108500
echo "waiting for helloweb service to get External-IP"
until kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done

service_ip=$(kubectl get services helloweb -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
curl -s ${service_ip}:80

cd $LAUNCH_DIR