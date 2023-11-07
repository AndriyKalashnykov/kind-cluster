[![End to End Tests](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml/badge.svg)](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml)
[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FAndriyKalashnykov%2Fkind-cluster&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# kind-cluster
Create local Kubernetes clusters using Docker with [KinD](https://kind.sigs.k8s.io/)


## Requirements

* [Docker](https://docs.docker.com/engine/install/)
* [kind](https://kind.sigs.k8s.io/docs/user/quick-start#installation)
* [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
* [helm](https://helm.sh/docs/intro/install/)
* [curl](https://help.ubidots.com/en/articles/2165289-learn-how-to-install-run-curl-on-windows-macosx-linux)
* [jq](https://github.com/stedolan/jq/wiki/Installation)
* [base64](https://command-not-found.com/base64)

## Help

```bash
make help
```

```text
help                               - List available tasks
install-all                        - Install all (kind k8s cluster, Nginx ingress, MetaLB, demo workloads)
install-all-no-demo-workloads      - Install all (kind k8s cluster, Nginx ingress, MetaLB)
create-cluster                     - Create k8s cluster
export-cert                        - Export k8s keys(client) and certificates(client, cluster CA)
k8s-dashboard                      - Install k8s dashboard
nginx-ingress                      - Install Nginx ingress
metallb                            - Install MetalLB load balancer
deploy-app-nginx-ingress-localhost - Deploy httpd web server and create an ingress rule for a localhost (http://demo.localdev.me:80/), Patch ingress-nginx-controller service type -> LoadBlancer
deploy-app-helloweb                - Deploy helloweb
deploy-app-golang-hello-world-web  - Deploy golang-hello-world-web app
deploy-app-foo-bar-service         - Deploy foo-bar-service app
delete-cluster                     - Delete K8s cluste
```

## Install all (kind k8s cluster, Nginx ingress, MetaLB, demo workloads)


```bash
./scripts/kind-install-all.sh
```

Or you can install each component individually

## Create k8s cluster


```bash
./scripts/kind-create.sh
```

## Export k8s keys(client) and certificates(client, cluster CA)


```bash
./scripts/kind-create.sh
```

Script creates:
- client.key
- client.crt
- client.pfx
- cluster-ca.crt

## Install k8s dashboard

Install k8s dashboard


```bash
./scripts/kind-add-dashboard.sh
```

Script creates file with admin-user token
- dashboard-admin-token.txt

## Launch k8s Dashboard

v3.0.0-alpha0

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
kubectl apply -n kubernetes-dashboard -f ./k8s/dashboard-admin.yaml
export dashboard_admin_token=$(kubectl get secret -n kubernetes-dashboard admin-user-token -o jsonpath="{.data.token}" | base64 --decode)
echo "${dashboard_admin_token}" > dashboard-admin-token.txt
kubectl config set-credentials cluster-admin --token=${dashboard_admin_token}
echo "Dashboard Token: ${dashboard_admin_token}"

export POD_NAME=$(kubectl get pods -n kubernetes-dashboard -l "app.kubernetes.io/name=kubernetes-dashboard,app.kubernetes.io/instance=kubernetes-dashboard" -o jsonpath="{.items[0].metadata.name}")
kubectl -n kubernetes-dashboard port-forward $POD_NAME 8443:8443
xdg-open "https://localhost:8443"

# helm delete kubernetes-dashboard --namespace kubernetes-dashboard
# kubectl delete clusterrolebinding --ignore-not-found=true kubernetes-dashboard
# kubectl delete clusterrole --ignore-not-found=true kubernetes-dashboard
```

v2.x

```bash
# kill kubectl proxy if already running
pkill -9 -f "kubectl proxy"
# start new kubectl proxy
kubectl proxy –address=’0.0.0.0′ –accept-hosts=’^*$’ &
# copy admin-user token to the clipboard
cat ./dashboard-admin-token.txt | xclip -i
# open dashboard
xdg-open "http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/" &
```

In Dashboard UI select "Token' and `Ctrl+V` 

## Install Nginx ingress


```bash
./scripts/kind-add-ingress-nginx.sh
```

## Install MetalLB load balancer


```bash
./scripts/kind-add-metallb.sh
```

## Deploy demo workloads

### Deploy httpd web server and create an ingress rule for a localhost `http://demo.localdev.me:80/`


```bash
./scripts/kind-deploy-app-nginx-ingress-localhost.sh
```

### Deploy helloweb


```bash
./scripts/kind-deploy-app-helloweb.sh
```

### Deploy golang-hello-world-web


```bash
./scripts/kind-deploy-app-golang-hello-world-web.sh
```

### Deploy foo-bar-service


```bash
./scripts/kind-deploy-app-foo-bar-service.sh
```

### Deploy Prometheus

Add prometheus and stable repo to local helm repository
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add stable https://charts.helm.sh/stable
helm repo update
```

Create namespace monitoring to deploy all services in that namespace
```bash
kubectl create namespace monitoring
```

Install kube-prometheus stack
```bash
helm template kind-prometheus prometheus-community/kube-prometheus-stack --namespace monitoring \
--set prometheus.service.nodePort=30000 \
--set prometheus.service.type=LoadBalancer \
--set grafana.service.nodePort=31000 \
--set grafana.service.type=LoadBalancer \
--set alertmanager.service.nodePort=32000 \
--set alertmanager.service.type=LoadBalancer \
--set prometheus-node-exporter.service.nodePort=32001 \
--set prometheus-node-exporter.service.type=LoadBalancer \
> ./k8s/prometheus.yaml

kubectl apply -f ./k8s/prometheus.yaml
kubectl --namespace monitoring get pods -l release=kind-prometheus
```

Delete kube-prometheus stack
```bash
kubectl delete -f ./k8s/prometheus.yaml
```

## Delete k8s cluster


```bash
./scripts/kind-delete.sh
```
