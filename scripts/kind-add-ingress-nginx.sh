#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

# https://github.com/kubernetes/ingress-nginx

echo "deploying nginx ingress for kind"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "waiting for nginx"
kubectl wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout=${TIMEOUT}

# https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md

# create a simple web server and the associated service
kubectl create deployment demo --image=httpd --port=80
kubectl expose deployment demo

# create an ingress resource. The following example uses a host that maps to localhost
kubectl create ingress demo-localhost --class=nginx --rule="demo.localdev.me/*=demo:80"
# kubectl port-forward --namespace=ingress-nginx service/ingress-nginx-controller 8080:80

curl  http://demo.localdev.me:8080/

cd $LAUNCH_DIR