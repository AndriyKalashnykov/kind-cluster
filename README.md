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

## Install NFS & nfs-subdir-external-provisioner to achieve RWX

* [Dynamic NFS Provisioning in Kubernetes Cluster](https://www.linuxtechi.com/dynamic-nfs-provisioning-kubernetes/)
* [ NFS Server and Client on Ubuntu 22.04](https://www.tecmint.com/install-nfs-server-on-ubuntu/)

```bash
sudo apt install -y nfs-kernel-server nfs-common

sudo mkdir -p /mnt/k8s_nfs_storage
sudo chown -R nobody:nogroup /mnt/k8s_nfs_storage
sudo chmod 777 /mnt/k8s_nfs_storage
```

get your host IP
```bash
hostname -I | awk '{print $1}'
```
```terminal
$ 192.168.1.27
```

let's allow any IP `*` (or you whole subnetwork `192.168.1.0/24`)

```bash
sudo vi /etc/exports
```

```txt
/mnt/k8s_nfs_storage *(rw,sync,no_subtree_check)
```

```bash
sudo exportfs -a
sudo systemctl restart nfs-kernel-server
sudo systemctl status nfs-kernel-server

# add firewall rules
# sudo ufw status
# sudo ufw allow from 192.168.1.27 to any port nfs
sudo ufw allow nfs
sudo ufw disable
sudo ufw status
```
```terminal
Status: active

To                         Action      From
--                         ------      ----
Nginx HTTP                 ALLOW       Anywhere                  
Nginx Full                 ALLOW       Anywhere                  
22/tcp                     DENY        Anywhere                  
2049                       ALLOW       192.168.1.27              
Nginx HTTP (v6)            ALLOW       Anywhere (v6)             
Nginx Full (v6)            ALLOW       Anywhere (v6)             
22/tcp (v6)                DENY        Anywhere (v6) 
```

mount it test if it worked

```
sudo mkdir -p /mnt/nfs_clientshare/
sudo mount -t nfs 192.168.1.27:/mnt/k8s_nfs_storage /mnt/nfs_clientshare/
sudo umount -f -l /mnt/nfs_clientshare/
```

Install the nfs-subdir-external-provisioner

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner

docker pull registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
kind load docker-image registry.k8s.io/sig-storage/nfs-subdir-external-provisioner:v4.0.2
helm install -n nfs-provisioning --create-namespace nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --set nfs.server=192.168.1.27 --set nfs.path=/mnt/k8s_nfs_storage

kubectl get all -n nfs-provisioning
kubectl get sc -n nfs-provisioning
```

```bash
kubectl create -f ./k8s/nfs/pvc.yaml
kubectl get pv,pvc -n nfs-provisioning
kubectl create -f ./k8s/nfs/pod.yaml
kubectl get pods -n nfs-provisioning
kubectl exec --stdin --tty -n nfs-provisioning test-pod -- /bin/sh
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
