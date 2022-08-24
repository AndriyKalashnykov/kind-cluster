#!/bin/sh
set -o errexit
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# https://cloud.google.com/kubernetes-engine/docs/tutorials/hello-app

docker pull gcr.io/google-samples/hello-app:1.0
docker tag gcr.io/google-samples/hello-app:1.0 localhost:5001/hello-app:1.0
docker push localhost:5001/hello-app:1.0
kubectl apply -f ./k8s/helloweb-deployment-local.yaml
curl http://localhost:8080

# kubectl create deployment hello-server --image=localhost:5001/hello-app:1.0
# kubectl delete deployment hello-server

cd $LAUNCH_DIR