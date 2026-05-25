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

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

# renovate: datasource=github-releases depName=kubernetes-csi/csi-driver-nfs
CSI_DRIVER_NFS_VERSION=v4.13.2

NS_DRIVER=kube-system
NS_SERVER=nfs-server
RELEASE=csi-driver-nfs

echo "=== Installing csi-driver-nfs ${CSI_DRIVER_NFS_VERSION} ==="
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
echo "=== Deploying in-cluster NFS server (namespace: ${NS_SERVER}) ==="
"${KUBECTL[@]}" apply -f ./k8s/nfs/nfs-server.yaml
"${KUBECTL[@]}" -n "$NS_SERVER" rollout status deployment/nfs-server --timeout=3m

echo
echo "=== Creating StorageClass 'nfs-csi' pointing at in-cluster NFS server ==="
"${KUBECTL[@]}" apply -f ./k8s/nfs/nfs-storageclass-incluster.yaml

echo
"${KUBECTL[@]}" get sc nfs-csi
echo
echo "Ready. Create a RWX PVC with:  storageClassName: nfs-csi"
echo "Test with:  kubectl apply -f ./k8s/nfs/pvc-incluster.yaml"

cd "$LAUNCH_DIR"
