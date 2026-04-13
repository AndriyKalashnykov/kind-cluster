#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# renovate: datasource=github-releases depName=metallb/metallb
METALLB_VERSION=v0.15.3

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


# https://metallb.universe.tf/
# https://github.com/metallb/metallb

# On v0.13.4 and older
echo "deploying metallb LoadBalancer"
kubectl apply -f  https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for metallb"
kubectl wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout="${TIMEOUT}"

# get kind IP — pick the IPv4 subnet (modern Docker lists IPv6 first when dual-stack)
echo "getting kind network IP"
ipv4_subnet=$(docker network inspect kind | jq -r '.[0].IPAM.Config[] | select(.Subnet | test("^[0-9]+\\.")) | .Subnet' | head -1)
ip_subclass=$(echo "${ipv4_subnet}" | awk -F. '{printf "%d.%d\n", $1, $2}')
if [ -z "${ip_subclass}" ] || [ "${ip_subclass}" = "0.0" ]; then
    echo "ERROR: failed to extract kind network IPv4 subnet from 'docker network inspect kind'"
    docker network inspect kind | jq '.[0].IPAM.Config'
    exit 1
fi
echo "kind network /16 prefix: ${ip_subclass}"

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

