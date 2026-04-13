#!/bin/bash
# Run `make install-all` inside the kind-host VM (non-interactive).
#
# Usage: vm-install-all.sh [NAME]

set -euo pipefail

NAME=${1:-kind-host}

if ! command -v multipass >/dev/null 2>&1; then
    echo "Error: multipass is not installed. Run: make vm-up" >&2
    exit 1
fi

if ! multipass info "$NAME" >/dev/null 2>&1; then
    echo "Error: VM '$NAME' does not exist. Create it with: make vm-up NAME=$NAME" >&2
    exit 1
fi

echo "=== Running 'make install-all' inside '$NAME' ==="
multipass exec "$NAME" -- bash -lc 'cd ~/kind-cluster && git pull --ff-only && make install-all'

echo
echo "=== Cluster ready inside VM '$NAME' ==="
echo "Get a shell:  make vm-ssh NAME=$NAME"
