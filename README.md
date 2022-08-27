[![End to End Tests](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml/badge.svg)](https://github.com/AndriyKalashnykov/kind-cluster/actions/workflows/end2end-tests.yml)
[![Hits](https://hits.seeyoufarm.com/api/count/incr/badge.svg?url=https%3A%2F%2Fgithub.com%2FAndriyKalashnykov%2Fkind-cluster&count_bg=%2379C83D&title_bg=%23555555&icon=&icon_color=%23E7E7E7&title=hits&edge_flat=false)](https://hits.seeyoufarm.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
# kind-cluster
Create local Kubernetes clusters using Docker container "nodes" using [kind](https://kind.sigs.k8s.io/)


## Install all at one (kind k8s cluster, Nginx ingress, MetaLB, demo workloads)

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

In terminal

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

## Delete k8s cluster

```bash
./scripts/kind-delete.sh
```
