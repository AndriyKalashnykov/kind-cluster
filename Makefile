.DEFAULT_GOAL := help

SHELL := /bin/bash

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-36s\033[0m - %s\n", $$1, $$2}'

#deps: @ Verify required tools are installed
deps:
	@for tool in docker kind kubectl helm curl jq base64; do \
		command -v $$tool >/dev/null 2>&1 || { echo "Error: $$tool required. See README Prerequisites."; exit 1; }; \
	done

#install-all: @ Install all (kind k8s cluster, Nginx ingress, MetalLB, demo workloads)
install-all: deps
	@./scripts/kind-install-all.sh yes

#install-all-no-demo-workloads: @ Install all (kind k8s cluster, Nginx ingress, MetalLB)
install-all-no-demo-workloads: deps
	@./scripts/kind-install-all.sh no

#kind-up: @ docker-compose-style alias for install-all (bring the whole stack up)
kind-up: install-all

#kind-down: @ docker-compose-style alias for delete-cluster (tear the whole stack down)
kind-down: delete-cluster

#create-cluster: @ Create k8s cluster
create-cluster: deps
	@./scripts/kind-create.sh

#export-cert: @ Export k8s keys (client) and certificates (client, cluster CA)
export-cert: deps
	@./scripts/kind-export-cert.sh

#dashboard-install: @ Install Kubernetes Dashboard (Helm chart v7.x) and admin ServiceAccount
dashboard-install: deps
	@./scripts/kind-add-dashboard.sh

#dashboard-forward: @ Port-forward dashboard to https://localhost:8443 and open browser
dashboard-forward: deps
	@./scripts/kind-forward-dashboard.sh

#dashboard-token: @ Print the admin-user token for the Dashboard login screen
dashboard-token: deps
	@./scripts/kind-dashboard-token.sh

#k8s-dashboard: @ Alias for dashboard-install (backwards compatible)
k8s-dashboard: dashboard-install

#nginx-ingress: @ Install Nginx ingress
nginx-ingress: deps
	@./scripts/kind-add-ingress-nginx.sh

#metallb: @ Install MetalLB load balancer
metallb: deps
	@./scripts/kind-add-metallb.sh

#metrics-server: @ Install metrics-server for kubectl top / HPA
metrics-server: deps
	@./scripts/kind-add-metrics-server.sh

#kube-prometheus-stack: @ Install kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
kube-prometheus-stack: deps
	@./scripts/kind-add-kube-prometheus-stack.sh

#nfs-incluster: @ Install in-cluster NFS server + csi-driver-nfs (RWX, no host config)
nfs-incluster: deps
	@./scripts/kind-add-nfs-incluster.sh

#nfs-host-setup: @ Configure HOST as NFS server (Ubuntu/Debian, requires sudo)
nfs-host-setup:
	@./scripts/kind-add-nfs-host-setup.sh

#nfs-host-provisioner: @ Install nfs-subdir-external-provisioner (pass NFS_SERVER=<ip>)
nfs-host-provisioner: deps
	@if [ -z "$(NFS_SERVER)" ]; then echo "Error: NFS_SERVER=<ip> required. Example: make nfs-host-provisioner NFS_SERVER=192.168.1.27"; exit 1; fi
	@./scripts/kind-add-nfs-host-provisioner.sh $(NFS_SERVER) $(if $(NFS_PATH),$(NFS_PATH),)

#deploy-app-nginx-ingress-localhost: @ Deploy httpd with ingress at http://demo.localdev.me:80/ (patches ingress-nginx-controller to LoadBalancer)
deploy-app-nginx-ingress-localhost: deps
	@./scripts/kind-deploy-app-nginx-ingress-localhost.sh

#deploy-app-helloweb: @ Deploy helloweb
deploy-app-helloweb: deps
	@./scripts/kind-deploy-app-helloweb.sh

#deploy-app-golang-hello-world-web: @ Deploy golang-hello-world-web app
deploy-app-golang-hello-world-web: deps
	@./scripts/kind-deploy-app-golang-hello-world-web.sh

#deploy-app-foo-bar-service: @ Deploy foo-bar-service app
deploy-app-foo-bar-service: deps
	@./scripts/kind-deploy-app-foo-bar-service.sh

#image-build: @ Build kubectl-test Docker image
image-build:
	@docker build -f ./images/Dockerfile -t kubectl-test .

#vm-up: @ Launch Ubuntu VM via Multipass with the full stack pre-provisioned (NAME=kind-host)
vm-up:
	@./scripts/vm-up.sh $(if $(NAME),$(NAME),) $(if $(CPUS),$(CPUS),) $(if $(MEMORY),$(MEMORY),) $(if $(DISK),$(DISK),)

#vm-down: @ Stop, delete and purge the VM (NAME=kind-host)
vm-down:
	@./scripts/vm-down.sh $(if $(NAME),$(NAME),)

#vm-ssh: @ Open an interactive shell inside the VM (NAME=kind-host)
vm-ssh:
	@./scripts/vm-ssh.sh $(if $(NAME),$(NAME),)

#vm-install-all: @ Run 'make install-all' inside the VM (NAME=kind-host)
vm-install-all:
	@./scripts/vm-install-all.sh $(if $(NAME),$(NAME),)

#renovate-validate: @ Validate renovate.json configuration
renovate-validate:
	@command -v npx >/dev/null 2>&1 || { echo "Error: npx required (install Node.js)."; exit 1; }
	@npx --yes --package renovate -- renovate-config-validator

#delete-cluster: @ Delete k8s cluster
delete-cluster: deps
	@./scripts/kind-delete.sh

.PHONY: help deps install-all install-all-no-demo-workloads kind-up kind-down \
	create-cluster export-cert k8s-dashboard dashboard-install \
	dashboard-forward dashboard-token nginx-ingress metallb \
	metrics-server kube-prometheus-stack \
	nfs-incluster nfs-host-setup nfs-host-provisioner \
	deploy-app-nginx-ingress-localhost deploy-app-helloweb \
	deploy-app-golang-hello-world-web deploy-app-foo-bar-service \
	image-build renovate-validate delete-cluster \
	vm-up vm-down vm-ssh vm-install-all
