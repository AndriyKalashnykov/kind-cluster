#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

./kind-export-cert.sh

./kind-add-dashboard.sh

./kind-add-ingress-nginx.sh

./kind-add-metallb.sh

./kind-deploy-app-helloweb.sh
./kind-deploy-app-golang-hello-world-web.sh
./kind-deploy-app-foo-bar-service.sh

cd $LAUNCH_DIR