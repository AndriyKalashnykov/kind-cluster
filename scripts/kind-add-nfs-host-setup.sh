#!/bin/bash
# Configure the HOST machine as an NFS server (Ubuntu/Debian).
# Requires sudo — this script touches /etc/exports, restarts nfs-kernel-server,
# and opens the firewall. Review before running.
#
# Companion: kind-add-nfs-host-provisioner.sh installs the in-cluster provisioner.
#
# Usage: kind-add-nfs-host-setup.sh [EXPORT_PATH] [ALLOW_FROM]
#   EXPORT_PATH  default: /mnt/k8s_nfs_storage
#   ALLOW_FROM   default: *   (any IP — tighten to a CIDR for anything real)
#
# After running, note the host IP (hostname -I | awk '{print $1}') and pass
# it to kind-add-nfs-host-provisioner.sh.

set -euo pipefail

EXPORT_PATH=${1:-/mnt/k8s_nfs_storage}
ALLOW_FROM=${2:-*}

if ! command -v apt-get >/dev/null 2>&1; then
    echo "Error: this script supports Debian/Ubuntu (apt-get). For other OS,"
    echo "install nfs-kernel-server manually and add \$EXPORT_PATH to /etc/exports."
    exit 1
fi

echo "=== Installing nfs-kernel-server ==="
sudo apt-get update -y
sudo apt-get install -y nfs-kernel-server nfs-common

echo
echo "=== Preparing export path: ${EXPORT_PATH} ==="
sudo mkdir -p "$EXPORT_PATH"
sudo chown -R nobody:nogroup "$EXPORT_PATH"
sudo chmod 777 "$EXPORT_PATH"

EXPORT_LINE="${EXPORT_PATH} ${ALLOW_FROM}(rw,sync,no_subtree_check,no_root_squash)"
echo
echo "=== Adding to /etc/exports (if not present) ==="
echo "  ${EXPORT_LINE}"
if ! sudo grep -qF "$EXPORT_PATH" /etc/exports 2>/dev/null; then
    echo "$EXPORT_LINE" | sudo tee -a /etc/exports >/dev/null
else
    echo "  (already present, skipping)"
fi

echo
echo "=== Applying exports and restarting nfs-kernel-server ==="
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
sudo systemctl status nfs-kernel-server --no-pager --lines=0 || true

echo
echo "=== Firewall (ufw) ==="
if command -v ufw >/dev/null 2>&1; then
    sudo ufw allow nfs || true
fi

HOST_IP=$(hostname -I | awk '{print $1}')
echo
echo "=== Done ==="
echo "  Host IP:      ${HOST_IP}"
echo "  Export path:  ${EXPORT_PATH}"
echo "  Allowed from: ${ALLOW_FROM}"
echo
echo "Verify the mount from any NFS client:"
echo "  sudo mount -t nfs ${HOST_IP}:${EXPORT_PATH} /mnt/test"
echo
echo "Next: install the in-cluster provisioner pointing at this host:"
echo "  ./scripts/kind-add-nfs-host-provisioner.sh ${HOST_IP} ${EXPORT_PATH}"
