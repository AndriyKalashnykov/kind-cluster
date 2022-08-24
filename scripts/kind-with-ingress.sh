#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# create cluster
kind create cluster --config=./config/config.yaml --name kind

# create ingress
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# create LoadBalancer
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml
# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
# kubectl get pods -n metallb-system --watch

# wait for metallb pods
# kubectl describe pod controller-7476b58756-5478b -n metallb-system
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout=90s

# get kind network IP
# iface="$(ip route | grep $(docker network inspect --format '{{json (index .IPAM.Config 0).Subnet}}' "kind" | tr -d '"') | cut -d ' ' -f 3)"
# docker network inspect kind -f '{{json (index .IPAM.Config 0).Subnet}}'
# docker network inspect kind | jq -r '.[].IPAM.Config[0].Subnet'
ip_subclass=$(docker network inspect kind -f '{{index .IPAM.Config 0 "Subnet"}}' | awk -F. '{printf "%d.%d\n", $1, $2}')

cat <<EOF | kubectl apply -f=-
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${ip_subclass}.255.200-${ip_subclass}.255.250
EOF

kubectl apply -f ./k8s/helloweb-deployment.yaml
kubectl get services

# kind delete cluster

cd $LAUNCH_DIR