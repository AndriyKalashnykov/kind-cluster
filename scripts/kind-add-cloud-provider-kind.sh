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

# CLOUD_PROVIDER_KIND_VERSION is pinned + exported by the Makefile where
# Renovate tracks it via the inline `# renovate:` comment. Require it
# here rather than duplicate the literal in two places (Makefile + script
# fallback would drift silently on a Renovate bump; the shell regex
# custom.regex manager can't parse ${VAR:-default} syntax anyway). Set
# manually if running the script outside `make lb-cpk` / `make install-all`.
# Value is the bare semver (e.g. 0.10.0); the docker tag is `v$VERSION`
# because Renovate strips the `v` via extractVersion.
: "${CLOUD_PROVIDER_KIND_VERSION:?set via Makefile or export CLOUD_PROVIDER_KIND_VERSION=X.Y.Z (bare semver)}"

# https://github.com/kubernetes-sigs/cloud-provider-kind
# CPK runs as a host docker container on the 'kind' network, reads docker.sock,
# and assigns LoadBalancer IPs to Services without needing MetalLB.

if "${KUBECTL[@]}" get ns metallb-system >/dev/null 2>&1; then
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

# --gateway-channel disabled: this lab serves the Gateway API via dedicated
# controllers (Traefik/Istio/NGF/Contour/Envoy/kgateway/Kong), NEVER via
# cloud-provider-kind's own Gateway API support, and CPK assigns LoadBalancer
# IPs to Services independently of its gateway channel. By default CPK
# force-installs its embedded Gateway API CRDs (v1.4.0, standard channel) at
# startup; on a cluster that already has the experimental Gateway API v1.5.1
# CRDs and their `safe-upgrades` ValidatingAdmissionPolicy (which denies
# installing any GW API CRD < v1.5.0), that install is DENIED and CPK aborts
# `Failed to start cloud controller` — it then NEVER assigns LoadBalancer IPs.
# This bit the MetalLB -> CPK migration whenever a gateway controller was
# already installed (the migration starts CPK after those CRDs + VAP exist).
# `disabled` skips CPK's GW API CRD reconcile entirely; the Service LoadBalancer
# controller is a separate code path started before any channel check
# (controller.go:238-253 @ v0.10.0), so LoadBalancer IP assignment is unaffected.
echo "starting cloud-provider-kind v${CLOUD_PROVIDER_KIND_VERSION} (gateway-channel disabled)"
docker run -d --restart on-failure \
    --name cloud-provider-kind \
    --network kind \
    -v /var/run/docker.sock:/var/run/docker.sock \
    registry.k8s.io/cloud-provider-kind/cloud-controller-manager:"v${CLOUD_PROVIDER_KIND_VERSION}" \
    --gateway-channel disabled

echo "cloud-provider-kind v${CLOUD_PROVIDER_KIND_VERSION} started on the 'kind' network"
