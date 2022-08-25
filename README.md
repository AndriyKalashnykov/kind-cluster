# kind-cluster
Create local Kubernetes clusters using Docker container "nodes"


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


## Install Kind cluster with Nginx ingress and Metallb load balancer

```bash
./scripts/kind-with-ingress.sh
```


## Delete k8s cluster

```bash
./scripts/kind-delete.sh
```