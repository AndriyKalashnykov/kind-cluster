#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR


./kind-export-cert.sh

./kind-add-dashboard.sh

./kind-add-ingress-nginx.sh


./kind-add-metallb.sh

echo "deploy helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml
echo "wait for deploy helloweb pods"
kubectl wait deployment -n default helloweb --for condition=Available=True --timeout=180s
# https://stackoverflow.com/questions/70108499/kubectl-wait-for-service-on-aws-eks-to-expose-elastic-load-balancer-elb-addres/70108500#70108500
echo "wait for helloweb service to get External-IP from LoadBalancer"
until kubectl get service/helloweb -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
kubectl get services helloweb -n default -o jsonpath="{.items[0].status.loadBalancer.ingress[0].hostname}"
helloweb_ip=$(kubectl get services helloweb -n default -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
curl ${helloweb_ip}:80

echo "deploy golang-hello-world-web"
# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
kubectl apply -f https://raw.githubusercontent.com/fabianlee/k3s-cluster-kvm/main/roles/golang-hello-world-web/templates/golang-hello-world-web.yaml.j2
echo "wait for deploy golang-hello-world-web pods"
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout=180s

echo "deploy foo-service"
kubectl apply -f https://kind.sigs.k8s.io/examples/loadbalancer/usage.yaml
echo "wait for foo-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout=180s
echo "wait for foo-service service to get External-IP from LoadBalancer"
until kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in {1..10}; do
  curl ${LB_IP}:5678
done


cd $LAUNCH_DIR