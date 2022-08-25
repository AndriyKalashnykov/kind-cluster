#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# https://metallb.universe.tf/
# https://github.com/metallb/metallb

# v0.13.4
echo "deploy metallb LoadBalancer"
kubectl apply -f  https://raw.githubusercontent.com/metallb/metallb/v0.13.4/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "wait for metallb"
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout=180s

# get kind IP
ip_subclass=$(docker network inspect kind -f '{{index .IPAM.Config 0 "Subnet"}}' | awk -F. '{printf "%d.%d\n", $1, $2}')

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

cd $LAUNCH_DIR