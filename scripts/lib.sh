#!/usr/bin/env bash
# Sourceable helper library for the kind-cluster scripts.
#
# Contains ONLY pure function definitions and no top-level side effects, so it
# can be sourced both by the scripts (scripts/*.sh) and by the bats unit tests
# (tests/lib.bats) without executing anything. Not meant to be run directly.
#
# Sourced via:  . "$SCRIPT_DIR/lib.sh"

# pf_local_port <port-forward-output>
#   Extract the local TCP port that `kubectl port-forward` chose, from its
#   "Forwarding from 127.0.0.1:<port> -> ..." status line. Prints the first
#   IPv4 match, or nothing when the output has no IPv4 forwarding line yet
#   (the [::1] IPv6 line is intentionally ignored).
pf_local_port() {
    local port
    port=$(printf '%s\n' "${1:-}" | sed -nE 's/.*127\.0\.0\.1:([0-9]+).*/\1/p')
    printf '%s' "${port%%$'\n'*}"
}

# kube_node_name <cluster-name>
#   KinD names the control-plane container "<cluster>-control-plane". Derive it
#   from the cluster name so an overridden KIND_CLUSTER_NAME still resolves the
#   right container for `docker exec`.
kube_node_name() {
    printf '%s' "${1:-kind}-control-plane"
}

# flag_enabled <value>
#   Succeeds only when an opt-in flag is exactly the string "yes" — the
#   convention used by TEST_MONITORING / TEST_METRICS_SERVER / TEST_NFS.
#   Anything else (including the YAML-boolean "true") is treated as off, which
#   is why the workflows quote the value as "yes".
flag_enabled() {
    [ "${1:-no}" = "yes" ]
}
