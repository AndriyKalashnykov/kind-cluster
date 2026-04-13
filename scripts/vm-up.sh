#!/bin/bash
# Launch an Ubuntu VM via Multipass with the kind-cluster stack pre-provisioned
# (Docker + kind + kubectl + helm + nfs-kernel-server).
#
# Usage: vm-up.sh [NAME] [CPUS] [MEMORY] [DISK]
#   NAME    default: kind-host
#   CPUS    default: 4
#   MEMORY  default: 8G
#   DISK    default: 40G
#
# Cloud-init provisioning lives in vm/cloud-init.yaml; bootstrap runs on first boot.
# Once it finishes, the VM is ready to `make install-all` inside. Expected time
# to first usable state: ~3-5 minutes (image download + package install + docker pull).

set -euo pipefail

LAUNCH_DIR=$(pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

NAME=${1:-kind-host}
CPUS=${2:-4}
MEMORY=${3:-8G}
DISK=${4:-40G}

if ! command -v multipass >/dev/null 2>&1; then
    cat <<EOF >&2
Error: multipass is not installed.

Install on Ubuntu/Debian:   sudo snap install multipass
Install on macOS:           brew install --cask multipass
Install on Windows:         winget install Canonical.Multipass

See https://multipass.run for other platforms.
EOF
    exit 1
fi

if multipass info "$NAME" >/dev/null 2>&1; then
    echo "VM '$NAME' already exists. To recreate, run: make vm-down NAME=$NAME"
    multipass info "$NAME"
    exit 0
fi

echo "=== Launching Multipass VM '$NAME' (${CPUS} CPU, ${MEMORY} RAM, ${DISK} disk) ==="
multipass launch \
    --name "$NAME" \
    --cpus "$CPUS" \
    --memory "$MEMORY" \
    --disk "$DISK" \
    --cloud-init vm/cloud-init.yaml \
    22.04

echo
echo "=== Waiting for cloud-init bootstrap to finish ==="
for i in $(seq 1 60); do
    if multipass exec "$NAME" -- test -f /var/lib/kind-cluster-bootstrapped 2>/dev/null; then
        echo "Bootstrap finished after ${i}0s."
        break
    fi
    printf "."
    sleep 10
done
echo

multipass info "$NAME"

cat <<EOF

=== VM ready ===
Connect:               make vm-ssh NAME=$NAME
Run full install:      multipass exec $NAME -- bash -c 'cd ~/kind-cluster && make install-all'
Forward service port:  multipass exec $NAME -- kubectl port-forward ...   (or run inside VM)
Tear down:             make vm-down NAME=$NAME

The project repo is already checked out at /home/ubuntu/kind-cluster inside the VM.
NFS export directory:  /srv/k8s_nfs_storage  (for make nfs-host-provisioner)
EOF

cd "$LAUNCH_DIR"
