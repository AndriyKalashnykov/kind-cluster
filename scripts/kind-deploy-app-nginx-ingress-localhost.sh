#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

TIMEOUT=${1:-180s}

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi


# https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md

echo "changing ingress-nginx-controller service type to LoadBlancer"
kubectl patch svc ingress-nginx-controller -n ingress-nginx --type='json' -p "[{\"op\":\"replace\",\"path\":\"/spec/type\",\"value\":\"LoadBalancer\"}]"
echo "waiting for ingress-nginx-controller service to get External-IP"
for _ in $(seq 1 90); do
    kubectl get service/ingress-nginx-controller -n ingress-nginx --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep 2
done
kubectl get service/ingress-nginx-controller -n ingress-nginx --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: ingress-nginx-controller did not get an External-IP after 180s"; kubectl get svc -n ingress-nginx ingress-nginx-controller; exit 1; }
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

# demo.localdev.me NXDOMAIN on many hosts (GH runners included); curl the
# ingress-nginx LoadBalancer IP directly from INSIDE the kind control-plane
# node with an explicit Host header. Retry up to 30s for async rule propagation.
KIND_NODE=$(docker ps --filter label=io.x-k8s.kind.role=control-plane --format '{{.Names}}' | head -1)
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in $(seq 1 15); do
    RESP=$(docker exec "${KIND_NODE}" curl -sf --max-time 5 -H "Host: demo.localdev.me" "http://${INGRESS_IP}:80/" 2>/dev/null) && { echo "$RESP" | head -c 200; echo; break; }
    sleep 2
done
[ -n "${RESP:-}" ] || echo "(curl http://${INGRESS_IP} via ${KIND_NODE} with Host demo.localdev.me failed after 30s)"

