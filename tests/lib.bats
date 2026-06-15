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
