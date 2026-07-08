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

# normalize_arch <uname-m-output>
#   Map a `uname -m` machine string to the Docker/OCI arch name
#   (x86_64 -> amd64, aarch64/arm64 -> arm64); pass anything else through.
#   Pure (no side effects) so it is unit-tested in tests/lib.bats.
normalize_arch() {
    case "${1:-}" in
        x86_64)        printf 'amd64' ;;
        aarch64|arm64) printf 'arm64' ;;
        *)             printf '%s' "${1:-}" ;;
    esac
}

# kind_load_image <image-ref> [cluster-name]
#   Load a (possibly multi-arch) image into a kind cluster WITHOUT the
#   kind#3795 "ctr: content digest not found" failure seen on Docker's
#   containerd image store. `kind load docker-image` pipes `docker save`
#   (which exports the full manifest LIST) into `ctr import --all-platforms`,
#   so the absent non-host-platform manifest blob aborts the import even after
#   a single-platform `docker pull`. Instead, export exactly ONE platform and
#   load it as an archive.
kind_load_image() {
    local image="$1" cluster="${2:-kind}" platform archive
    platform="linux/$(normalize_arch "$(uname -m)")"
    docker pull --platform="$platform" "$image"
    archive="$(mktemp)"
    # `docker save --platform` (Docker >= 28) exports one platform even from the
    # containerd image store. Older Docker lacks the flag, but its preceding
    # `docker pull --platform` already left a single-platform image in the
    # legacy store, so a plain `docker save` is single-platform there too.
    if ! docker save --platform="$platform" "$image" -o "$archive" 2>/dev/null; then
        docker save "$image" -o "$archive"
    fi
    kind load image-archive "$archive" --name "$cluster"
    rm -f "$archive"
}

# dash_ip <dotted-ipv4>
#   Convert a dotted IPv4 (172.18.0.6) to the dash form sslip.io accepts in a
#   hostname label (172-18-0-6). Pure; unit-tested in tests/lib.bats.
dash_ip() {
    printf '%s' "${1:-}" | tr '.' '-'
}

# sslip_host <label> <dotted-ipv4>
#   Build the sslip.io hostname that resolves to <ip> for a given app <label>,
#   e.g. sslip_host helloweb 172.18.0.6 -> helloweb.172-18-0-6.sslip.io. sslip.io
#   returns the embedded IP regardless of the leading label, so this is how each
#   per-LB-IP gateway exposes the demo apps over real (resolvable) HTTPS names.
#   Pure; unit-tested in tests/lib.bats.
sslip_host() {
    printf '%s.%s.sslip.io' "${1:-}" "$(dash_ip "${2:-}")"
}

# check_host_port <port>
#   Return 0 when TCP <port> is FREE on 127.0.0.1, non-zero when something is
#   already listening on it. A SUCCESSFUL /dev/tcp connect means the port is
#   TAKEN (return 1); a failed connect or timeout means it is FREE (return 0).
#   Pure probe — reads nothing, writes nothing; the fd lives only in the
#   `timeout bash -c` child, so it is closed when that child exits.
check_host_port() {
    if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/${1:-0}" 2>/dev/null; then
        return 1
    fi
    return 0
}

# check_ports <port>...
#   Preflight the fixed host ports a target is about to bind. For every port
#   already in use, print an actionable line naming the likely holder (the docker
#   container publishing it, or a generic hint to free it / override the matching
#   *_PORT var). Return non-zero if ANY port is taken, 0 when all are free.
#   Side effects are limited to the messages it prints (no binds, no mutations),
#   so it stays safe to source into the bats suite.
check_ports() {
    local p holder conflict=0
    for p in "$@"; do
        if check_host_port "$p"; then
            continue
        fi
        holder=$(docker ps --filter "publish=$p" --format '{{.Names}}' 2>/dev/null | paste -sd, -)
        if [ -n "$holder" ]; then
            echo "ERROR: host port $p is already in use by container(s): $holder"
        else
            echo "ERROR: something is bound to 127.0.0.1:$p; free it or override the matching *_PORT var (INGRESS_HTTP_PORT / INGRESS_HTTPS_PORT / HEADLAMP_LOCAL_PORT / REGISTRY_PORT)."
        fi
        conflict=1
    done
    if [ "$conflict" -eq 0 ]; then
        echo "check-ports: all requested host ports are free (${*:-none})."
    fi
    return "$conflict"
}
