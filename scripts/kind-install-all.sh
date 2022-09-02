#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

./scripts/kind-create.sh

./scripts/kind-export-cert.sh

./scripts/kind-add-dashboard.sh

./scripts/kind-add-ingress-nginx.sh

./scripts/kind-add-metallb.sh

./scripts/kind-deploy-app-nginx-ingress-localhost.sh
./scripts/kind-deploy-app-helloweb.sh
./scripts/kind-deploy-app-golang-hello-world-web.sh
./scripts/kind-deploy-app-foo-bar-service.sh

cd $LAUNCH_DIR