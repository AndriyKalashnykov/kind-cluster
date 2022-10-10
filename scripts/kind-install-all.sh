#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

INSTALL_DEMO_WORKLOADS=${1:-yes}

cd $SCRIPT_PARENT_DIR

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

cd $LAUNCH_DIR
