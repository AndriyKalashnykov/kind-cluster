#!/bin/bash
# Open an interactive shell into the kind-host VM.
#
# Usage: vm-ssh.sh [NAME]

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

exec multipass shell "$NAME"
