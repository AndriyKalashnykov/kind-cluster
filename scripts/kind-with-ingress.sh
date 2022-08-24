#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# https://cloudyuga.guru/hands_on_lab/kind-k8s
kind create cluster --config=./config/config.yaml --name kind
docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"
CONTEXT="kind-kind"

CERTIFICATE=$(kubectl config view --raw -o json | jq -r '.users[] | select(.name == "'${CONTEXT}'") | .user."client-certificate-data"')
KEY=$(kubectl config view --raw -o json | jq -r '.users[] | select(.name == "'${CONTEXT}'") | .user."client-key-data"')
CLUSTER_CA=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'${CONTEXT}'") | .cluster."certificate-authority-data"')

echo ${CERTIFICATE} | base64 -d > client.crt
echo ${KEY} | base64 -d > client.key

openssl pkcs12 -export -in client.crt -inkey client.key -out client.pfx -passout pass:

rm client.crt
rm client.key

echo ${CLUSTER_CA} | base64 -d > cluster.crt

# https://github.com/kubernetes/ingress-nginx
echo "deploy nginx ingress for kind"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
echo "wait for nginx pods"
kubectl wait pods -n ingress-nginx -l app.kubernetes.io/component=controller --for condition=Ready --timeout=90s

# https://metallb.universe.tf/
# https://github.com/metallb/metallb

# v0.12.1
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
# kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# v0.13.4
echo "deploy metallb LoadBalancer"
kubectl apply -f  https://raw.githubusercontent.com/metallb/metallb/v0.13.4/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
# kubectl get pods -n metallb-system --watch

echo "wait for metallb pods"
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout=90s

# get kind network IP
# iface="$(ip route | grep $(docker network inspect --format '{{json (index .IPAM.Config 0).Subnet}}' "kind" | tr -d '"') | cut -d ' ' -f 3)"
# docker network inspect kind -f '{{json (index .IPAM.Config 0).Subnet}}'
# docker network inspect kind | jq -r '.[].IPAM.Config[0].Subnet'
ip_subclass=$(docker network inspect kind -f '{{index .IPAM.Config 0 "Subnet"}}' | awk -F. '{printf "%d.%d\n", $1, $2}')

# v0.12.1
# cat <<EOF | kubectl apply -f=-
# apiVersion: v1
# kind: ConfigMap
# metadata:
#   namespace: metallb-system
#   name: config
# data:
#   config: |
#     address-pools:
#     - name: default
#       protocol: layer2
#       addresses:
#       - ${ip_subclass}.255.200-${ip_subclass}.255.250
# EOF

# v0.13.4
# https://thr3a.hatenablog.com/entry/20220718/1658127951
# https://github.com/metallb/metallb/issues/1473
cat <<EOF | kubectl apply -f=-
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - ${ip_subclass}.255.200-${ip_subclass}.255.250
  autoAssign: true
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec:
  ipAddressPools:
  - default
EOF

echo "deploy helloweb"
kubectl apply -f ./k8s/helloweb-deployment.yaml
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
kubectl wait deployment -n default golang-hello-world-web --for condition=Available=True --timeout=90s

echo "deploy foo-service"
kubectl apply -f https://kind.sigs.k8s.io/examples/loadbalancer/usage.yaml
echo "wait for foo-service pods"
kubectl wait pods -n default -l app=http-echo --for condition=Ready --timeout=90s
echo "wait for foo-service service to get External-IP from LoadBalancer"
until kubectl get service/foo-service -n default --output=jsonpath='{.status.loadBalancer}' | grep "ingress"; do : ; done &&
LB_IP=$(kubectl get svc/foo-service -o=jsonpath='{.status.loadBalancer.ingress[0].ip}')
for _ in {1..10}; do
  curl ${LB_IP}:5678
done

# kind delete cluster

cd $LAUNCH_DIR