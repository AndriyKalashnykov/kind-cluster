#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1


# https://kind.sigs.k8s.io/
# https://cloudyuga.guru/hands_on_lab/kind-k8s

if kind get clusters | grep -q '^kind$'; then
    echo "Kind cluster Cluster exists skipping creation ..."
    echo "Switching context to kind ..."
    kubectl config use-context kind-kind
else
kind create cluster --config=./k8s/kind-config.yaml --name kind --wait 10s
docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"
fi

