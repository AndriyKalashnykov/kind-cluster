#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

INSTALL_DEMO_WORKLOADS=${1:-yes}


./scripts/kind-create.sh

./scripts/kind-export-cert.sh

./scripts/kind-add-dashboard.sh

./scripts/kind-add-ingress-nginx.sh

./scripts/kind-add-metallb.sh


# case insensitive comparison
shopt -s nocasematch
if [[ $INSTALL_DEMO_WORKLOADS == yes ]]; then
    ./scripts/kind-deploy-app-nginx-ingress-localhost.sh
    ./scripts/kind-deploy-app-helloweb.sh
    ./scripts/kind-deploy-app-golang-hello-world-web.sh
    ./scripts/kind-deploy-app-foo-bar-service.sh
fi

