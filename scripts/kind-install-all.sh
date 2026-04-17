#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

INSTALL_DEMO_WORKLOADS=${1:-yes}

LB=${LB:-cpk}
LB=$(echo "$LB" | tr '[:upper:]' '[:lower:]')
case "$LB" in
    cpk|metallb) ;;
    *)
        echo "ERROR: unknown LB provider '$LB' (expected 'cpk' or 'metallb')"
        exit 1
        ;;
esac
echo "Selected LoadBalancer: $LB"


./scripts/kind-create.sh

./scripts/kind-export-cert.sh

./scripts/kind-add-dashboard.sh

./scripts/kind-add-ingress-nginx.sh

if [ "$LB" = "cpk" ]; then
    ./scripts/kind-add-cloud-provider-kind.sh
else
    ./scripts/kind-add-metallb.sh
fi


# case insensitive comparison
shopt -s nocasematch
if [[ $INSTALL_DEMO_WORKLOADS == yes ]]; then
    ./scripts/kind-deploy-app-nginx-ingress-localhost.sh
    ./scripts/kind-deploy-app-helloweb.sh
    ./scripts/kind-deploy-app-golang-hello-world-web.sh
    ./scripts/kind-deploy-app-foo-bar-service.sh
fi

