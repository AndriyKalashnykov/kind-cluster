#!/bin/bash
# Switch an already-running cluster from MetalLB to cloud-provider-kind (CPK)
# without tearing down the cluster. Use this if you ran `LB=metallb make install-all`
# (or a pre-rework `make install-all`) and now want to move to CPK.
#
# Order matters — CPK refuses to start if MetalLB is still present; MetalLB
# refuses to uninstall cleanly while workloads reference LoadBalancer IPs from
# its pool. The safe sequence:
#   1. Scale LoadBalancer services down? No — they keep their IPs while we swap.
#      The new provider will re-allocate on its own range when MetalLB goes away.
#   2. Delete MetalLB's IPAddressPool / L2Advertisement (so MetalLB stops assigning).
#   3. Delete the MetalLB namespace (controller + speaker DaemonSet + CRDs).
#   4. Start CPK.
#   5. Kick existing LoadBalancer services to re-allocate on the new pool.

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

if ! kubectl get ns metallb-system >/dev/null 2>&1; then
    echo "No metallb-system namespace found — nothing to migrate."
    echo "If you meant to install CPK on a fresh cluster, run: make lb-cpk"
    exit 0
fi

# Idempotency: if CPK is already running, bail with instructions.
if docker ps --filter name=cloud-provider-kind --format '{{.Names}}' | grep -qx cloud-provider-kind; then
    echo "cloud-provider-kind container is already running."
    echo "Finish the migration by removing MetalLB manually:"
    echo "  kubectl delete -A ipaddresspools.metallb.io --all --ignore-not-found"
    echo "  kubectl delete -A l2advertisements.metallb.io --all --ignore-not-found"
    echo "  kubectl delete namespace metallb-system"
    exit 1
fi

echo "Step 1/4: Removing MetalLB IPAddressPool / L2Advertisement CRs..."
kubectl delete -A ipaddresspools.metallb.io --all --ignore-not-found
kubectl delete -A l2advertisements.metallb.io --all --ignore-not-found

echo "Step 2/4: Deleting the metallb-system namespace (takes the controller + speaker + CRDs with it)..."
kubectl delete namespace metallb-system --ignore-not-found --timeout=120s

echo "Step 3/4: Starting cloud-provider-kind..."
./scripts/kind-add-cloud-provider-kind.sh

echo "Step 4/4: Re-allocating LoadBalancer IPs for existing Services..."
# Kick each LoadBalancer Service so CPK assigns a new ExternalIP. This is a
# no-op for Services that already have an IP from CPK's pool, and a re-roll
# for any still holding a stale MetalLB IP.
while IFS= read -r svc; do
    [ -z "$svc" ] && continue
    ns=$(echo "$svc" | cut -d/ -f1)
    name=$(echo "$svc" | cut -d/ -f2)
    echo "  kicking $svc"
    kubectl patch -n "$ns" svc "$name" --type=merge -p '{"spec":{"type":"ClusterIP"}}' >/dev/null
    kubectl patch -n "$ns" svc "$name" --type=merge -p '{"spec":{"type":"LoadBalancer"}}' >/dev/null
done < <(kubectl get svc -A -o jsonpath='{range .items[?(@.spec.type=="LoadBalancer")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}')

echo "Migration complete. Verify with: kubectl get svc -A | grep LoadBalancer"
