#!/bin/bash
# Install nfs-subdir-external-provisioner pointing at a HOST-SIDE NFS server.
# The host must already export a directory over NFS — run
# kind-add-nfs-host-setup.sh first.
#
# Architecture:
#   app-pod --(RWX PVC)--> nfs-client StorageClass --(subdir-provisioner)--> Host NFS server --> /srv/...
#
# Usage: kind-add-nfs-host-provisioner.sh NFS_SERVER_IP [NFS_PATH]
#   NFS_SERVER_IP  required, e.g. 192.168.1.27
#   NFS_PATH       default: /srv/k8s_nfs_storage
#
# References:
#   https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner

set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 NFS_SERVER_IP [NFS_PATH]"
    echo "  Run kind-add-nfs-host-setup.sh first and pass the printed host IP."
    exit 1
fi

LAUNCH_DIR=$(pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

NFS_SERVER=$1
NFS_PATH=${2:-/srv/k8s_nfs_storage}

# renovate: datasource=helm depName=nfs-subdir-external-provisioner registryUrl=https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
NFS_SUBDIR_PROVISIONER_VERSION=4.0.18

NS=nfs-provisioning

echo "=== Installing nfs-subdir-external-provisioner ${NFS_SUBDIR_PROVISIONER_VERSION} ==="
echo "    NFS server: ${NFS_SERVER}:${NFS_PATH}"

helm repo add nfs-subdir-external-provisioner \
    https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner >/dev/null 2>&1 || true
helm repo update nfs-subdir-external-provisioner >/dev/null

helm upgrade --install nfs-subdir-external-provisioner \
    nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
    --namespace "$NS" --create-namespace \
    --version "${NFS_SUBDIR_PROVISIONER_VERSION}" \
    --set nfs.server="${NFS_SERVER}" \
    --set nfs.path="${NFS_PATH}" \
    --wait --timeout 5m

kubectl get sc nfs-client
echo
echo "Ready. Create a RWX PVC with:  storageClassName: nfs-client"
echo "Test with:  kubectl apply -f ./k8s/nfs/pvc.yaml"

cd "$LAUNCH_DIR"
