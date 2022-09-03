#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

# https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md

echo "changing ingress-nginx-controller service type to LoadBlancer"
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p "[{\"op\":\"replace\",\"path\":\"/spec/type\",\"value\":\"LoadBalancer\"}]"
echo "waiting for ingress-nginx-controller service to get External-IP"
until kubectl get service/ingress-nginx-controller -n ingress-nginx --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
service_ip=$(kubectl get services ingress-nginx-controller -n ingress-nginx -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "nginx ingress External-IP: ${service_ip}"

echo "deploying a httpd web server and the associated service"
DEMO_SVC_NAME=demo-localhost
DEMO_SVC_PORT=80
kubectl create deployment demo-localhost --image=httpd --port=${DEMO_SVC_PORT}
echo "waiting for httpd pods"
kubectl wait deployment -n default demo-localhost --for condition=Available=True --timeout=${TIMEOUT}
kubectl expose deployment ${DEMO_SVC_NAME}

echo "creating an ingress resource and mapping demo.localdev.me to localhost"
kubectl create ingress demo-localhost --class=nginx --rule="demo.localdev.me/*=${DEMO_SVC_NAME}:${DEMO_SVC_PORT}"

echo "waiting for ingress demo-localhost"
wait_period=0
hostname=""
while [ -z $hostname ]; do
  echo "Waiting for hostname ..."
  hostname=$(kubectl get --namespace default ingress/demo-localhost --template="{{range .status.loadBalancer.ingress}}{{.hostname}}{{end}}")
  if [ -z "$hostname" ];then
    sleep 10
    wait_period=$(($wait_period+10))
  fi

  wait_timeout=$(echo $TIMEOUT | sed 's/[^0-9]*//g')
  if [ $wait_period -gt $wait_timeout ];then
    echo "Didn't get the hostname, timeout reached"
    break
  fi
done
echo "ingress demo-localhost hostname: $hostname"

# kubectl port-forward --namespace=ingress-nginx service/ingress-nginx-controller 8080:${DEMO_SVC_PORT}

curl -s http://demo.localdev.me:80/

cd $LAUNCH_DIR