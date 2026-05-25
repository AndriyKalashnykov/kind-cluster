#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Use an explicit kubectl context so a parallel `make` invocation in
# another KinD project (which may run `kubectl config use-context`)
# cannot silently switch us to the wrong cluster mid-script. Default
# is `kind` for backward compat with existing tooling that references
# the `kind-kind` context.
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"
KUBECTL=(kubectl --context="kind-${KIND_CLUSTER_NAME}")

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

# LB provider must be installed BEFORE Traefik — Traefik's helm chart
# creates a Service of type LoadBalancer and `helm --wait` blocks until
# .status.loadBalancer is populated, which only happens once a LB
# controller (cloud-provider-kind or MetalLB) is running.
if [ "$LB" = "cpk" ]; then
    ./scripts/kind-add-cloud-provider-kind.sh
else
    ./scripts/kind-add-metallb.sh
fi

./scripts/kind-add-headlamp.sh

./scripts/kind-add-traefik.sh


# case insensitive comparison
shopt -s nocasematch
if [[ $INSTALL_DEMO_WORKLOADS == yes ]]; then
    ./scripts/kind-deploy-app-ingress-localhost.sh
    ./scripts/kind-deploy-app-helloweb.sh
    ./scripts/kind-deploy-app-golang-hello-world-web.sh
    ./scripts/kind-deploy-app-foo-bar-service.sh
    # Bundled ingress rules for helloweb / golang / foo (the demo-localhost
    # ingress for httpd is created by kind-deploy-app-ingress-localhost.sh).
    # Applied after the services exist so Traefik can resolve its backends.
    # The wait blocks until Traefik populates .status.loadBalancer — so
    # anyone running `make e2e` immediately after install-all doesn't race
    # the controller's reconcile of the new rules.
    echo "applying demo-apps ingress rules"
    "${KUBECTL[@]}" apply -f ./k8s/demo-apps-ingress.yaml
    # Traefik writes .status.loadBalancer.ingress[0] (.ip when cloud-provider-kind
    # / MetalLB assigns one, .hostname when --publish-status-address is set).
    # Poll for any field being non-empty on the first array element.
    for _ in $(seq 1 60); do
        [ -n "$("${KUBECTL[@]}" get ingress/demo-apps -o jsonpath='{.status.loadBalancer.ingress[0]}' 2>/dev/null)" ] && break
        sleep 1
    done
    "${KUBECTL[@]}" get ingress/demo-apps -o jsonpath='{.status.loadBalancer.ingress[0]}' | grep -q . \
        || { echo "ERROR: demo-apps ingress did not propagate after 60s"; "${KUBECTL[@]}" get ingress/demo-apps -o yaml; exit 1; }
fi

