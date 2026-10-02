#!/usr/bin/env bats
# RED-proofs for scripts/check-toolchain-alignment.sh (the first prereq of
# `make static-check`). Run via `make test` (bats).
#
# Fixtures are SYNTHETIC and use versions that cannot be the real pins
# (kubectl 9.8.7, kind 0.99.1). That is deliberate:
#   - the exact "OK (kubectl=9.8.7, kind=0.99.1)" line proves the script read the
#     temp tree and not the real repo (a real-tree copy would pass identically if
#     the ROOT argument were ignored);
#   - `make test` does not go red on a half-bumped Renovate PR for a reason that
#     has nothing to do with this script. The real files' shapes are checked by
#     the gate itself on every `make static-check`.
#
# Drift cases assert the <file>=<value> PAIRING with a sentinel (9.8.6 / 0.99.0),
# not merely that a file name appears: the drift message names every file
# whichever pin moved.

KUBECTL=9.8.7
KIND=0.99.1

setup() {
    local here
    here="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    SCRIPT="$here/../scripts/check-toolchain-alignment.sh"
    TREE="$BATS_TEST_TMPDIR/tree"
    mktree "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KIND" "$KIND"
}

# mktree <makefile-kubectl> <mise-kubectl> <dockerfile-kubectl> <cloud-init-kubectl> <mise-kind> <cloud-init-kind>
# Mirrors the real files' shapes, including the neighbouring lines that must NOT
# be mistaken for pins (a --build-arg use, a comment naming the tool, a ${VAR} use).
mktree() {
    rm -rf "$TREE"
    mkdir -p "$TREE/images" "$TREE/vm"
    printf '%s\n' \
        '# renovate: datasource=github-tags depName=kubernetes/kubernetes' \
        "KUBECTL_VERSION := v$1" \
        'image-build:' \
        '	docker build --build-arg KUBECTL_VERSION=$(KUBECTL_VERSION) images/' \
        > "$TREE/Makefile"
    printf '%s\n' \
        '[tools]' \
        '# jq and kubectl need a renovate.json packageRule each (kubernetes/kubectl tags).' \
        "\"aqua:kubernetes-sigs/kind\" = \"$5\"" \
        "\"aqua:kubernetes/kubectl\"   = \"$2\"" \
        > "$TREE/.mise.toml"
    printf '%s\n' \
        'FROM alpine' \
        "ARG KUBECTL_VERSION=v$3" \
        'RUN echo "${KUBECTL_VERSION}"' \
        > "$TREE/images/Dockerfile"
    printf '%s\n' \
        'write_files:' \
        '  - content: |' \
        "      KIND_VERSION=v$6" \
        "      KUBECTL_VERSION=v$4" \
        '      curl -fsSLo kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"' \
        > "$TREE/vm/cloud-init.yaml"
}

# drop_line <file-relative-to-TREE> <fixed-string>: delete the lines containing it.
drop_line() {
    local f="$TREE/$1"
    grep -vF -- "$2" "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
}

# --- positive control --------------------------------------------------------

@test "alignment: aligned synthetic tree passes and reports the SYNTHETIC versions" {
    run "$SCRIPT" "$TREE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Toolchain alignment OK (kubectl=$KUBECTL, kind=$KIND)." ]
}

@test "alignment: a v-prefixed mise pin is still aligned" {
    mktree "$KUBECTL" "v$KUBECTL" "$KUBECTL" "$KUBECTL" "v$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Toolchain alignment OK (kubectl=$KUBECTL, kind=$KIND)." ]
}

@test "alignment: a trailing comment after a pin does not change the value read" {
    printf '%s\n' '[tools]' \
        "\"aqua:kubernetes-sigs/kind\" = \"$KIND\"" \
        "\"aqua:kubernetes/kubectl\"   = \"$KUBECTL\" # was = \"9.8.6\"" \
        > "$TREE/.mise.toml"
    run "$SCRIPT" "$TREE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Toolchain alignment OK (kubectl=$KUBECTL, kind=$KIND)." ]
}

@test "alignment: a non-existent root fails and says so" {
    run "$SCRIPT" "$BATS_TEST_TMPDIR/does-not-exist"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: root directory not found"* ]]
}

# --- drift: each pin, asserted by <file>=<sentinel> pairing -------------------

@test "alignment: kubectl drift in the Makefile is reported against the Makefile" {
    mktree 9.8.6 "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"kubectl version drift"* ]]
    [[ "$output" == *"Makefile=9.8.6 .mise.toml=$KUBECTL images/Dockerfile=$KUBECTL vm/cloud-init.yaml=$KUBECTL"* ]]
}

@test "alignment: kubectl drift in .mise.toml is reported against .mise.toml" {
    mktree "$KUBECTL" 9.8.6 "$KUBECTL" "$KUBECTL" "$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Makefile=$KUBECTL .mise.toml=9.8.6 images/Dockerfile=$KUBECTL vm/cloud-init.yaml=$KUBECTL"* ]]
}

@test "alignment: kubectl drift in images/Dockerfile is reported against the Dockerfile" {
    mktree "$KUBECTL" "$KUBECTL" 9.8.6 "$KUBECTL" "$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Makefile=$KUBECTL .mise.toml=$KUBECTL images/Dockerfile=9.8.6 vm/cloud-init.yaml=$KUBECTL"* ]]
}

@test "alignment: kubectl drift in vm/cloud-init.yaml is reported against cloud-init" {
    mktree "$KUBECTL" "$KUBECTL" "$KUBECTL" 9.8.6 "$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Makefile=$KUBECTL .mise.toml=$KUBECTL images/Dockerfile=$KUBECTL vm/cloud-init.yaml=9.8.6"* ]]
}

@test "alignment: kind drift in .mise.toml is reported against .mise.toml" {
    mktree "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KUBECTL" 0.99.0 "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"kind version drift — .mise.toml=0.99.0 vm/cloud-init.yaml=$KIND"* ]]
}

@test "alignment: kind drift in vm/cloud-init.yaml is reported against cloud-init" {
    mktree "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KUBECTL" "$KIND" 0.99.0
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"kind version drift — .mise.toml=$KIND vm/cloud-init.yaml=0.99.0"* ]]
}

# --- missing pin: the original silent failure (rc!=0 with no file named) ------

@test "alignment: missing Makefile kubectl pin names the tool and the file" {
    drop_line Makefile 'KUBECTL_VERSION :='
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in Makefile, found 0"* ]]
}

@test "alignment: missing .mise.toml kubectl pin names the tool and the file" {
    drop_line .mise.toml '"aqua:kubernetes/kubectl"'
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in .mise.toml, found 0"* ]]
}

@test "alignment: missing Dockerfile kubectl ARG names the tool and the file" {
    drop_line images/Dockerfile 'ARG KUBECTL_VERSION='
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in images/Dockerfile, found 0"* ]]
}

@test "alignment: missing cloud-init kubectl pin names the tool and the file" {
    drop_line vm/cloud-init.yaml '      KUBECTL_VERSION='
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in vm/cloud-init.yaml, found 0"* ]]
}

@test "alignment: missing .mise.toml kind pin names the tool and the file" {
    drop_line .mise.toml '"aqua:kubernetes-sigs/kind"'
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kind: expected exactly 1 pin line in .mise.toml, found 0"* ]]
}

@test "alignment: missing cloud-init kind pin names the tool and the file" {
    drop_line vm/cloud-init.yaml 'KIND_VERSION='
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kind: expected exactly 1 pin line in vm/cloud-init.yaml, found 0"* ]]
}

@test "alignment: a missing input file is named" {
    rm "$TREE/images/Dockerfile"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: images/Dockerfile not found"* ]]
}

# --- duplicated / reshaped pins ----------------------------------------------

@test "alignment: a duplicated pin line is rejected with its count" {
    printf '      KUBECTL_VERSION=v%s\n' "$KUBECTL" >> "$TREE/vm/cloud-init.yaml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in vm/cloud-init.yaml, found 2"* ]]
}

@test "alignment: a second Makefile assignment with a different operator is counted" {
    printf 'KUBECTL_VERSION ?= v%s\n' "$KUBECTL" >> "$TREE/Makefile"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in Makefile, found 2"* ]]
}

@test "alignment: a non-version value is rejected as unparseable, naming the file" {
    drop_line Makefile 'KUBECTL_VERSION :='
    printf 'KUBECTL_VERSION := latest\n' >> "$TREE/Makefile"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: unparseable pin in Makefile"* ]]
}

@test "alignment: an unquoted mise pin is rejected as unparseable, naming the file" {
    drop_line .mise.toml '"aqua:kubernetes/kubectl"'
    printf '"aqua:kubernetes/kubectl" = %s\n' "$KUBECTL" >> "$TREE/.mise.toml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: unparseable pin in .mise.toml"* ]]
}

# --- added after implementation review ----------------------------------------

@test "alignment: an EMPTY root argument fails instead of checking this repo" {
    run "$SCRIPT" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: root argument is empty"* ]]
}

# Two missing pins of the SAME tool give two empty values, and "" == "" — so this
# case fails only if pin()'s abort actually stops the script. A single missing
# pin cannot tell that apart from a later drift failure.
@test "alignment: both kind pins missing fails and never prints the OK line" {
    drop_line .mise.toml '"aqua:kubernetes-sigs/kind"'
    drop_line vm/cloud-init.yaml 'KIND_VERSION='
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" != *"Toolchain alignment OK"* ]]
    [[ "$output" == *"ERROR: kind: expected exactly 1 pin line in .mise.toml, found 0"* ]]
}

# A commented-out pin alone is not a pin. These pin each regex's ^ anchor.
@test "alignment: a commented-out Makefile pin alone is not counted" {
    drop_line Makefile 'KUBECTL_VERSION :='
    printf '# KUBECTL_VERSION := v%s\n' "$KUBECTL" >> "$TREE/Makefile"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in Makefile, found 0"* ]]
}

@test "alignment: a commented-out .mise.toml kubectl pin alone is not counted" {
    drop_line .mise.toml '"aqua:kubernetes/kubectl"'
    printf '# "aqua:kubernetes/kubectl" = "%s"\n' "$KUBECTL" >> "$TREE/.mise.toml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in .mise.toml, found 0"* ]]
}

@test "alignment: a commented-out .mise.toml kind pin alone is not counted" {
    drop_line .mise.toml '"aqua:kubernetes-sigs/kind"'
    printf '# "aqua:kubernetes-sigs/kind" = "%s"\n' "$KIND" >> "$TREE/.mise.toml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kind: expected exactly 1 pin line in .mise.toml, found 0"* ]]
}

@test "alignment: a commented-out Dockerfile ARG alone is not counted" {
    drop_line images/Dockerfile 'ARG KUBECTL_VERSION='
    printf '# ARG KUBECTL_VERSION=v%s\n' "$KUBECTL" >> "$TREE/images/Dockerfile"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in images/Dockerfile, found 0"* ]]
}

@test "alignment: a commented-out cloud-init kubectl pin alone is not counted" {
    drop_line vm/cloud-init.yaml '      KUBECTL_VERSION='
    printf '      # KUBECTL_VERSION=v%s\n' "$KUBECTL" >> "$TREE/vm/cloud-init.yaml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: expected exactly 1 pin line in vm/cloud-init.yaml, found 0"* ]]
}

@test "alignment: a commented-out cloud-init kind pin alone is not counted" {
    drop_line vm/cloud-init.yaml 'KIND_VERSION='
    printf '      # KIND_VERSION=v%s\n' "$KIND" >> "$TREE/vm/cloud-init.yaml"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kind: expected exactly 1 pin line in vm/cloud-init.yaml, found 0"* ]]
}

@test "alignment: a tab-indented recipe line setting KUBECTL_VERSION is not a second pin" {
    printf 'smoke:\n\tKUBECTL_VERSION=v%s ./run.sh\n' "$KUBECTL" >> "$TREE/Makefile"
    run "$SCRIPT" "$TREE"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "Toolchain alignment OK (kubectl=$KUBECTL, kind=$KIND)." ]
}

@test "alignment: a pre-release value is rejected as unparseable even when all pins agree" {
    mktree "$KUBECTL-rc.1" "$KUBECTL-rc.1" "$KUBECTL-rc.1" "$KUBECTL-rc.1" "$KIND" "$KIND"
    run "$SCRIPT" "$TREE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"ERROR: kubectl: unparseable pin in Makefile"* ]]
}
