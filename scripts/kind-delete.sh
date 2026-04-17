#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1


# CPK (if present) must be removed BEFORE kind tears down the docker network —
# otherwise CPK is left as a zombie container bound to a phantom network.
docker rm -f cloud-provider-kind 2>/dev/null || true

kind delete cluster --name kind

