#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

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
    # Fail fast if the ingress host ports are already bound (by another cluster,
    # a stray container, or a host service), so creation errors clearly here
    # instead of kind failing cryptically on the port bind. check_ports (lib.sh)
    # prints the holder of any taken port.
    if ! check_ports "${INGRESS_HTTP_PORT:-80}" "${INGRESS_HTTPS_PORT:-443}"; then
        echo "Aborting cluster creation: an ingress host port is already in use (see above)."
        echo "Free it, or override with INGRESS_HTTP_PORT / INGRESS_HTTPS_PORT."
        exit 1
    fi

    # Render kind-config.yaml with the chosen host-side ingress ports. Only the
    # two host-side `hostPort:` values are substituted; `containerPort:` stays
    # 80/443. The defaults (80/443) render a file identical to the committed one,
    # so behavior is unchanged unless INGRESS_HTTP_PORT/INGRESS_HTTPS_PORT are set.
    RENDERED_CONFIG="$(mktemp -t kind-config.XXXXXX.yaml)"
    trap 'rm -f "$RENDERED_CONFIG"' EXIT
    sed -e "s/^\([[:space:]]*\)hostPort: 80$/\1hostPort: ${INGRESS_HTTP_PORT:-80}/" \
        -e "s/^\([[:space:]]*\)hostPort: 443$/\1hostPort: ${INGRESS_HTTPS_PORT:-443}/" \
        ./k8s/kind-config.yaml > "$RENDERED_CONFIG"

    KIND_ARGS=(--config="$RENDERED_CONFIG" --name "${KIND_CLUSTER_NAME}" --wait 60s)
    if [ -n "${KIND_NODE_IMAGE:-}" ]; then
        KIND_ARGS+=(--image="$KIND_NODE_IMAGE")
    fi
    kind create cluster "${KIND_ARGS[@]}"
    docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"
fi
