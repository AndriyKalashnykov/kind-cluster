#!/bin/bash
# Create a KinD cluster wired to a local Docker registry at localhost:5001.
# Useful for pushing locally-built images (e.g., `docker push localhost:5001/app:tag`)
# and having them pulled by pods without an external registry.
#
# Cluster name defaults to 'kind-registry' so it can coexist with a default
# 'kind' cluster (from `make install-all`). Override with CLUSTER_NAME.
#
# Uses the modern containerd registry config (config_path + per-registry
# hosts.toml) — the older `registry.mirrors` syntax breaks kubelet on
# containerd 2.x in recent kindest/node images.
#
# References:
#   https://kind.sigs.k8s.io/docs/user/local-registry/
#
# Usage: kind-with-registry.sh
# Env:   CLUSTER_NAME  default: kind-registry

set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-kind-registry}

# 1. Start the registry container if not already running.
reg_name='kind-registry'
reg_port='5001'
if [ "$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --network bridge --name "${reg_name}" \
    registry:2
fi

# 2. Create the cluster, pointing containerd at /etc/containerd/certs.d
#    (per-registry hosts.toml written in step 3).
cat <<EOF | kind create cluster --name "${CLUSTER_NAME}" --wait 2m --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    config_path = "/etc/containerd/certs.d"
EOF

# 3. Per the KinD docs: write a hosts.toml inside each node that redirects
#    localhost:${reg_port} -> http://kind-registry:5000 (the registry hostname
#    on the kind network, joined below).
REGISTRY_DIR="/etc/containerd/certs.d/localhost:${reg_port}"
for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" tee "${REGISTRY_DIR}/hosts.toml" >/dev/null
[host."http://${reg_name}:5000"]
EOF
done

# 4. Connect the registry to the cluster network so the kind nodes can reach it.
if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  docker network connect "kind" "${reg_name}"
fi

# 5. Document the local registry (enhancement kep-1755).
# https://github.com/kubernetes/enhancements/tree/master/keps/sig-cluster-lifecycle/generic/1755-communicating-a-local-registry
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: local-registry-hosting
  namespace: kube-public
data:
  localRegistryHosting.v1: |
    host: "localhost:${reg_port}"
    help: "https://kind.sigs.k8s.io/docs/user/local-registry/"
EOF

echo
echo "=== Done ==="
echo "Cluster:     ${CLUSTER_NAME} (kubectl context: kind-${CLUSTER_NAME})"
echo "Registry:    localhost:${reg_port}  (container: ${reg_name})"
echo "Test push:   docker push localhost:${reg_port}/<image>:<tag>"
