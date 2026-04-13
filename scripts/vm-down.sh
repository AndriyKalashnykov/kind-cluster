#!/bin/bash
# Stop and delete the kind-host VM (and purge it from Multipass).
#
# Usage: vm-down.sh [NAME]

set -euo pipefail

NAME=${1:-kind-host}

if ! command -v multipass >/dev/null 2>&1; then
    echo "multipass not installed — nothing to tear down."
    exit 0
fi

if ! multipass info "$NAME" >/dev/null 2>&1; then
    echo "VM '$NAME' does not exist."
    exit 0
fi

echo "=== Stopping and deleting VM '$NAME' ==="
multipass stop "$NAME" 2>/dev/null || true
multipass delete "$NAME"
multipass purge

echo "VM '$NAME' removed."
