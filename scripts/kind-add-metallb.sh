#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

GITHUB_URL=https://github.com/metallb/metallb/releases
METALLB_VERSION=$(curl -w '%{url_effective}' -I -L -s -S ${GITHUB_URL}/latest -o /dev/null | sed -e 's|.*/||')

VERSION=${1:-$METALLB_VERSION}
TIMEOUT=${2:-180s}

if [ -z "$VERSION" ]; then
    echo "Provide MetalLB version"
    exit 1
fi

if [ -z "$TIMEOUT" ]; then
    echo "Provide deployment timeout"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

# https://metallb.universe.tf/
# https://github.com/metallb/metallb

# On v0.13.4 and older
echo "deploying metallb LoadBalancer"
kubectl apply -f  https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for metallb"
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout=${TIMEOUT}

# get kind IP
echo "getting kind network IP"
ip_subclass=$(docker network inspect kind -f '{{index .IPAM.Config 0 "Subnet"}}' | awk -F. '{printf "%d.%d\n", $1, $2}')

# https://thr3a.hatenablog.com/entry/20220718/1658127951
# https://github.com/metallb/metallb/issues/1473
# On v0.13.4 and older
echo "creating kind IPAddressPool and L2Advertisement"
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