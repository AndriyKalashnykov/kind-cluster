#!/usr/bin/env bats
# Unit tests for scripts/lib.sh — the sourceable helpers shared by the
# kind-cluster scripts. Run via `make test` (bats).
#
# These tests source the REAL scripts/lib.sh (not a copy), so a regression in
# the helper logic fails here.

setup() {
    local here
    here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    # shellcheck source=scripts/lib.sh
    source "$here/../scripts/lib.sh"
}

# --- pf_local_port -----------------------------------------------------------

@test "pf_local_port: extracts the port from typical kubectl port-forward output" {
    run pf_local_port "Forwarding from 127.0.0.1:43215 -> 80
Forwarding from [::1]:43215 -> 80"
    [ "$status" -eq 0 ]
    [ "$output" = "43215" ]
}

@test "pf_local_port: ignores IPv6-only output (no IPv4 line -> empty)" {
    run pf_local_port "Forwarding from [::1]:51000 -> 80"
    [ "$output" = "" ]
}

@test "pf_local_port: empty input yields empty output" {
    run pf_local_port ""
    [ "$output" = "" ]
}

@test "pf_local_port: skips leading log noise" {
    run pf_local_port "some unrelated log line
Forwarding from 127.0.0.1:8081 -> 80"
    [ "$output" = "8081" ]
}

@test "pf_local_port: returns only the first match" {
    run pf_local_port "Forwarding from 127.0.0.1:1111 -> 80
Forwarding from 127.0.0.1:2222 -> 80"
    [ "$output" = "1111" ]
}

# --- kube_node_name ----------------------------------------------------------

@test "kube_node_name: derives <cluster>-control-plane" {
    run kube_node_name kind
    [ "$output" = "kind-control-plane" ]
    run kube_node_name foo
    [ "$output" = "foo-control-plane" ]
}

@test "kube_node_name: defaults to 'kind' when called with no argument" {
    run kube_node_name
    [ "$status" -eq 0 ]
    [ "$output" = "kind-control-plane" ]
}

# --- flag_enabled ------------------------------------------------------------

@test "flag_enabled: succeeds for exactly 'yes'" {
    run flag_enabled yes
    [ "$status" -eq 0 ]
}

@test "flag_enabled: fails for 'no'" {
    run flag_enabled no
    [ "$status" -ne 0 ]
}

@test "flag_enabled: fails for the YAML-boolean 'true' (quoting guard)" {
    run flag_enabled true
    [ "$status" -ne 0 ]
}

@test "flag_enabled: fails for empty and unset" {
    run flag_enabled ""
    [ "$status" -ne 0 ]
    run flag_enabled
    [ "$status" -ne 0 ]
}

# --- normalize_arch ----------------------------------------------------------

@test "normalize_arch: x86_64 maps to amd64" {
    run normalize_arch x86_64
    [ "$output" = "amd64" ]
}

@test "normalize_arch: aarch64 maps to arm64" {
    run normalize_arch aarch64
    [ "$output" = "arm64" ]
}

@test "normalize_arch: arm64 passes through as arm64" {
    run normalize_arch arm64
    [ "$output" = "arm64" ]
}

@test "normalize_arch: an unknown machine passes through unchanged" {
    run normalize_arch riscv64
    [ "$output" = "riscv64" ]
}

@test "normalize_arch: empty/unset yields empty" {
    run normalize_arch ""
    [ "$output" = "" ]
    run normalize_arch
    [ "$output" = "" ]
}

# --- dash_ip / sslip_host ----------------------------------------------------

@test "dash_ip: converts dotted IPv4 to dash form" {
    run dash_ip 172.18.0.6
    [ "$output" = "172-18-0-6" ]
}

@test "dash_ip: empty input yields empty" {
    run dash_ip ""
    [ "$output" = "" ]
}

@test "sslip_host: builds <label>.<dashed-ip>.sslip.io" {
    run sslip_host helloweb 172.18.0.6
    [ "$output" = "helloweb.172-18-0-6.sslip.io" ]
}

@test "sslip_host: a different IP and label" {
    run sslip_host golang 172.18.0.10
    [ "$output" = "golang.172-18-0-10.sslip.io" ]
}

@test "check_host_port: reports a FREE port as available (rc 0)" {
    # 59651 is in the ephemeral range and almost never bound at test time.
    run check_host_port 59651
    [ "$status" -eq 0 ]
}

@test "check_host_port: detects a BOUND port (rc non-zero)" {
    local port=59652 ready="$BATS_TEST_TMPDIR/listener_ready"
    python3 - "$port" "$ready" <<'PY' &
import socket, sys, time
p, ready = int(sys.argv[1]), sys.argv[2]
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", p)); s.listen(1)
open(ready, "w").close()
time.sleep(5)
PY
    local lpid=$!
    # Wait for the listener to actually be bound before probing (no race).
    for _ in $(seq 1 20); do [ -f "$ready" ] && break; sleep 0.1; done
    run check_host_port "$port"
    kill "$lpid" 2>/dev/null || true
    [ "$status" -ne 0 ]
}

@test "check_ports: rc 0 when all ports free" {
    run check_ports 59653 59654
    [ "$status" -eq 0 ]
}

# --- metallb_manifest_url ----------------------------------------------------
# MetalLB's git tags are v-prefixed; METALLB_VERSION is a bare semver because
# Renovate's extractVersion strips the v. PR #407 interpolated the bare value
# into the raw URL and every MetalLB install 404'd (main red 2026-11-04..).

@test "metallb_manifest_url: a bare semver gets the v-prefixed tag ref" {
    run metallb_manifest_url 0.16.2
    [ "$status" -eq 0 ]
    [ "$output" = "https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml" ]
}

@test "metallb_manifest_url: a v-prefixed version is not double-prefixed" {
    run metallb_manifest_url v0.16.2
    [ "$status" -eq 0 ]
    [ "$output" = "https://raw.githubusercontent.com/metallb/metallb/v0.16.2/config/manifests/metallb-native.yaml" ]
}

@test "metallb_manifest_url: an empty version fails and prints nothing" {
    run metallb_manifest_url ""
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}

@test "metallb_manifest_url: a bare 'v' fails and prints nothing" {
    run metallb_manifest_url v
    [ "$status" -ne 0 ]
    [ "$output" = "" ]
}
