#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1


# CPK (if present) must be removed BEFORE kind tears down the docker network —
# otherwise CPK is left as a zombie container bound to a phantom network.
# CPK spawns one `kindccm-<hash>` Envoy sidecar per LoadBalancer Service; these
# survive `kind delete` and orphan-hold subnet IPs across runs. A subsequent
# `kind-up` lands on an orphan's IP and inherits its stale Envoy config
# (pointed at dead pods), surfacing as `curl: (56) Recv failure` on first hit.
# Prune them here (before the cluster goes away) so the `kind` network is clean.
docker rm -f cloud-provider-kind 2>/dev/null || true
KINDCCM=$(docker ps -aq --filter name=kindccm- 2>/dev/null || true)
if [ -n "$KINDCCM" ]; then
    # shellcheck disable=SC2086 # word-splitting intended; one ID per arg
    docker rm -f $KINDCCM >/dev/null 2>&1 || true
fi

kind delete cluster --name kind

