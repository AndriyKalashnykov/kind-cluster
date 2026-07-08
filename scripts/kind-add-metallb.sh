#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

if docker ps --filter name=cloud-provider-kind --format '{{.Names}}' | grep -qx cloud-provider-kind; then
    echo "ERROR: cloud-provider-kind container is running."
    echo "MetalLB and cloud-provider-kind cannot coexist. Remove CPK first:"
    echo "  docker rm -f cloud-provider-kind"
    exit 1
fi

# renovate: datasource=github-tags depName=metallb/metallb extractVersion=^v(?<version>.*)$
METALLB_VERSION=v0.16.1

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
"${KUBECTL[@]}" apply -f  https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml

# https://fabianlee.org/2022/01/27/kubernetes-using-kubectl-to-wait-for-condition-of-pods-deployments-services/
echo "waiting for metallb"
"${KUBECTL[@]}" wait pods -n metallb-system -l app=metallb --for condition=Ready --timeout="${TIMEOUT}"

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
metallb_crs=$(cat <<EOF
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
)

# MetalLB's validating webhook (metallb-webhook-service -> controller pod) can
# refuse connections for a few seconds AFTER the controller pod reports Ready:
# the readiness probe passes before the webhook's HTTPS server + cert are
# actually serving, so an immediate apply fails with
# "failed calling webhook ... connect: connection refused".
# Retry until the webhook accepts the resources — "webhook ready" == "apply
# succeeds" — mirroring the K1.5 route-readiness poll the e2e harness uses.
applied=""
for _ in $(seq 1 "${POLL_ATTEMPTS:-30}"); do
    if printf '%s\n' "$metallb_crs" | "${KUBECTL[@]}" apply -f=- 2>/tmp/metallb-apply.err; then
        applied=yes
        break
    fi
    sleep "${POLL_INTERVAL:-2}"
done
if [ -z "$applied" ]; then
    echo "ERROR: IPAddressPool/L2Advertisement apply failed after 60s (webhook never became ready)"
    cat /tmp/metallb-apply.err 2>/dev/null || true
    "${KUBECTL[@]}" -n metallb-system get pods,svc,endpoints
    rm -f /tmp/metallb-apply.err
    exit 1
fi
rm -f /tmp/metallb-apply.err

