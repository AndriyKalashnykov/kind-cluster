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


# https://medium.com/@charled.breteche/kind-fix-missing-prometheus-operator-targets-1a1ff5d8c8ad

# Chart version pinned (was floating on `latest`). Renovate's scripts
# custom.regex manager bumps it via the inline comment below.
# renovate: datasource=helm depName=kube-prometheus-stack registryUrl=https://prometheus-community.github.io/helm-charts
KUBE_PROMETHEUS_STACK_VERSION=87.10.1

helm upgrade --install --wait --timeout 15m \
  --namespace monitoring --create-namespace \
  --repo https://prometheus-community.github.io/helm-charts \
  --version "${KUBE_PROMETHEUS_STACK_VERSION}" \
  kube-prometheus-stack kube-prometheus-stack --values - <<EOF
kubeEtcd:
  service:
    targetPort: 2381
EOF

"${KUBECTL[@]}" --namespace monitoring get pods -l "release=kube-prometheus-stack"

echo "changing kube-prometheus-stack-grafana service type to LoadBlancer"
"${KUBECTL[@]}" patch svc kube-prometheus-stack-grafana -n monitoring --type='json' -p "[{\"op\":\"replace\",\"path\":\"/spec/type\",\"value\":\"LoadBalancer\"}]"

echo "waiting for kube-prometheus-stack-grafana service to get External-IP"
for _ in $(seq 1 "${POLL_ATTEMPTS:-90}"); do
    "${KUBECTL[@]}" get service/kube-prometheus-stack-grafana -n monitoring --output=jsonpath='{.status.loadBalancer}' 2>/dev/null | grep -q "ingress" && break
    sleep "${POLL_INTERVAL:-2}"
done
"${KUBECTL[@]}" get service/kube-prometheus-stack-grafana -n monitoring --output=jsonpath='{.status.loadBalancer}' | grep -q "ingress" || { echo "ERROR: grafana did not get an External-IP after 180s"; "${KUBECTL[@]}" get svc -n monitoring kube-prometheus-stack-grafana; exit 1; }

# User: admin
# Pwd:  prom-operator
echo -n "Grafana User: " && "${KUBECTL[@]}" get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-user}" | base64 --decode ; echo 
echo -n "Grafana Pwd:  " && "${KUBECTL[@]}" get secret kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode ; echo

service_ip=$("${KUBECTL[@]}" get services kube-prometheus-stack-grafana -n monitoring -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
echo "Grafana URL: ${service_ip}:80/"
# xdg-open  ${service_ip}:80/

# kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# xdg-open http://localhost:9090/targets

