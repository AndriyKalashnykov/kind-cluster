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

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

NFS_SERVER=$1
NFS_PATH=${2:-/srv/k8s_nfs_storage}

# renovate: datasource=github-releases depName=kubernetes-csi/csi-driver-nfs
CSI_DRIVER_NFS_VERSION=v4.13.3

NS_DRIVER=kube-system
RELEASE=csi-driver-nfs
SC_NAME=nfs-host

echo "=== Ensuring csi-driver-nfs ${CSI_DRIVER_NFS_VERSION} is installed ==="
echo "    NFS server: ${NFS_SERVER}:${NFS_PATH}"

# Install the chart from the per-release tarball URL directly — bypasses
# `helm repo add`+index.yaml. The committed index.yaml at the v4.13.x tags
# rewrites `urls:` to point at the `release-4.12` maintenance branch (which
# lacks newer versions), so `helm repo add` against the release tag returns
# chart names but the resolved download URL 404s. The per-version tarball
# under `charts/${TAG}/csi-driver-nfs-${VER}.tgz` is the canonical artifact.
# Renovate tracks CSI_DRIVER_NFS_VERSION via the comment above.
CHART_URL="https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/${CSI_DRIVER_NFS_VERSION}/charts/${CSI_DRIVER_NFS_VERSION}/csi-driver-nfs-${CSI_DRIVER_NFS_VERSION#v}.tgz"

helm upgrade --install "$RELEASE" "$CHART_URL" \
    --namespace "$NS_DRIVER" \
    --wait --timeout 5m

echo
echo "=== Creating StorageClass '${SC_NAME}' pointing at ${NFS_SERVER}:${NFS_PATH} ==="
cat <<EOF | "${KUBECTL[@]}" apply -f -
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
"${KUBECTL[@]}" get sc "${SC_NAME}"
echo
echo "Ready. Create a RWX PVC with:  storageClassName: ${SC_NAME}"
echo "Test with:  kubectl apply -f ./k8s/nfs/pvc.yaml"

cd "$LAUNCH_DIR"
