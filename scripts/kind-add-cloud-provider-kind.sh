#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

CLOUD_PROVIDER_KIND_VERSION=${CLOUD_PROVIDER_KIND_VERSION:-v0.10.0}

# https://github.com/kubernetes-sigs/cloud-provider-kind
# CPK runs as a host docker container on the 'kind' network, reads docker.sock,
# and assigns LoadBalancer IPs to Services without needing MetalLB.

if kubectl get ns metallb-system >/dev/null 2>&1; then
    echo "ERROR: MetalLB is already installed (namespace 'metallb-system' exists)."
    echo "cloud-provider-kind and MetalLB cannot coexist. Remove MetalLB first:"
    echo "  kubectl delete ns metallb-system"
    echo "or re-run with 'LB=metallb make install-all' if you meant MetalLB."
    exit 1
fi

if ! docker network inspect kind >/dev/null 2>&1; then
    echo "ERROR: docker network 'kind' not found. Create the cluster first:"
    echo "  ./scripts/kind-create.sh"
    exit 1
fi

if docker ps --filter name=cloud-provider-kind --format '{{.Names}}' | grep -qx cloud-provider-kind; then
    echo "cloud-provider-kind container already running, skipping"
    exit 0
fi

# Clean any stopped container with the same name (idempotent re-runs).
docker rm -f cloud-provider-kind 2>/dev/null || true

echo "starting cloud-provider-kind ${CLOUD_PROVIDER_KIND_VERSION}"
docker run -d --restart on-failure \
    --name cloud-provider-kind \
    --network kind \
    -v /var/run/docker.sock:/var/run/docker.sock \
    registry.k8s.io/cloud-provider-kind/cloud-controller-manager:"${CLOUD_PROVIDER_KIND_VERSION}"

echo "cloud-provider-kind ${CLOUD_PROVIDER_KIND_VERSION} started on the 'kind' network"
