#!/bin/bash
# Install in-cluster NFS server + csi-driver-nfs + StorageClass for RWX volumes.
#
# Fully self-contained: no host-side NFS config, no sudo, no /etc/exports.
# An NFS server pod runs inside the cluster; csi-driver-nfs provisions PVs
# backed by that server. Suitable for local dev/demo. Data lives on the pod's
# emptyDir and does NOT survive a cluster teardown.
#
# Architecture:
#   app-pod --(RWX PVC)--> nfs StorageClass --(csi-driver-nfs)--> nfs-server (in-cluster) --> emptyDir
#
# Usage: kind-add-nfs-incluster.sh
#
# References:
#   https://github.com/kubernetes-csi/csi-driver-nfs

set -euo pipefail

LAUNCH_DIR=$(pwd)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# renovate: datasource=github-releases depName=kubernetes-csi/csi-driver-nfs
CSI_DRIVER_NFS_VERSION=v4.13.2

NS_DRIVER=kube-system
NS_SERVER=nfs-server
RELEASE=csi-driver-nfs

echo "=== Installing csi-driver-nfs ${CSI_DRIVER_NFS_VERSION} ==="
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts >/dev/null 2>&1 || true
helm repo update csi-driver-nfs >/dev/null

helm upgrade --install "$RELEASE" csi-driver-nfs/csi-driver-nfs \
    --namespace "$NS_DRIVER" \
    --version "${CSI_DRIVER_NFS_VERSION}" \
    --wait --timeout 5m

echo
echo "=== Deploying in-cluster NFS server (namespace: ${NS_SERVER}) ==="
kubectl apply -f ./k8s/nfs/nfs-server.yaml
kubectl -n "$NS_SERVER" rollout status deployment/nfs-server --timeout=3m

echo
echo "=== Creating StorageClass 'nfs-csi' pointing at in-cluster NFS server ==="
kubectl apply -f ./k8s/nfs/nfs-storageclass-incluster.yaml

echo
kubectl get sc nfs-csi
echo
echo "Ready. Create a RWX PVC with:  storageClassName: nfs-csi"
echo "Test with:  kubectl apply -f ./k8s/nfs/pvc-incluster.yaml"

cd "$LAUNCH_DIR"
