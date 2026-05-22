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
