#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Cluster name: defaults to "kind" when invoked outside `make` (preserves
# backward compat with existing tooling and docs that reference the
# `kind-kind` context). The Makefile exports KIND_CLUSTER_NAME via
# `export`, so `make kind-create` always sets it to whatever the caller
# (or the Makefile default of `kind`) chose.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"

# https://kind.sigs.k8s.io/
# https://cloudyuga.guru/hands_on_lab/kind-k8s

if kind get clusters | grep -q "^${KIND_CLUSTER_NAME}$"; then
    echo "Kind cluster '${KIND_CLUSTER_NAME}' exists, skipping creation ..."
    echo "Switching context to kind-${KIND_CLUSTER_NAME} ..."
    # `kubectl config use-context` IS the global current-context switch.
    # This is the only place we mutate kubeconfig — every other script
    # uses an explicit --context=kind-${KIND_CLUSTER_NAME} flag so the
    # current-context doesn't matter for them. See CLAUDE.md
    # "Conventions and exceptions".
    kubectl config use-context "kind-${KIND_CLUSTER_NAME}"
else
    KIND_ARGS=(--config=./k8s/kind-config.yaml --name "${KIND_CLUSTER_NAME}" --wait 60s)
    if [ -n "${KIND_NODE_IMAGE:-}" ]; then
        KIND_ARGS+=(--image="$KIND_NODE_IMAGE")
    fi
    kind create cluster "${KIND_ARGS[@]}"
    docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"
fi
