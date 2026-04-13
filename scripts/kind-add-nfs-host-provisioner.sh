#!/bin/bash
# Install csi-driver-nfs and create a StorageClass pointing at a HOST-SIDE
# NFS server. The host must already export a directory over NFS — run
# kind-add-nfs-host-setup.sh first.
#
# Uses the same csi-driver-nfs as Option 1, so the two options coexist: only
# the StorageClass differs. Replaces the unmaintained
# nfs-subdir-external-provisioner (last release 2023-03-13).
#
# Architecture:
#   app-pod --(RWX PVC)--> StorageClass nfs-host --(csi-driver-nfs)--> Host NFS server --> /srv/...
#
# Usage: kind-add-nfs-host-provisioner.sh NFS_SERVER_IP [NFS_PATH]
#   NFS_SERVER_IP  required, e.g. 192.168.1.27
#   NFS_PATH       default: /srv/k8s_nfs_storage
#
# References:
#   https://github.com/kubernetes-csi/csi-driver-nfs

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

# renovate: datasource=github-releases depName=kubernetes-csi/csi-driver-nfs
CSI_DRIVER_NFS_VERSION=v4.13.1

NS_DRIVER=kube-system
RELEASE=csi-driver-nfs
SC_NAME=nfs-host

echo "=== Ensuring csi-driver-nfs ${CSI_DRIVER_NFS_VERSION} is installed ==="
echo "    NFS server: ${NFS_SERVER}:${NFS_PATH}"

helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts >/dev/null 2>&1 || true
helm repo update csi-driver-nfs >/dev/null

helm upgrade --install "$RELEASE" csi-driver-nfs/csi-driver-nfs \
    --namespace "$NS_DRIVER" \
    --version "${CSI_DRIVER_NFS_VERSION}" \
    --wait --timeout 5m

echo
echo "=== Creating StorageClass '${SC_NAME}' pointing at ${NFS_SERVER}:${NFS_PATH} ==="
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${SC_NAME}
provisioner: nfs.csi.k8s.io
parameters:
  server: ${NFS_SERVER}
  share: ${NFS_PATH}
  mountPermissions: "0777"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
  - nolock
EOF

echo
kubectl get sc "${SC_NAME}"
echo
echo "Ready. Create a RWX PVC with:  storageClassName: ${SC_NAME}"
echo "Test with:  kubectl apply -f ./k8s/nfs/pvc.yaml"

cd "$LAUNCH_DIR"
