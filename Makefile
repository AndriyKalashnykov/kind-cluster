#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-34s\033[0m - %s\n", $$1, $$2}'

#install-all: @ Install all (kind k8s cluster, Nginx ingress, MetaLB, demo workloads)
install-all:
	./scripts/kind-install-all.sh yes

#install-all-no-demo-workloads: @ Install all (kind k8s cluster, Nginx ingress, MetaLB)
install-all-no-demo-workloads:
	./scripts/kind-install-all.sh no

#create-cluster: @ Create k8s cluster
create-cluster:
	./scripts/kind-create.sh

#export-cert: @ Export k8s keys(client) and certificates(client, cluster CA)
export-cert:
	./scripts/kind-export-cert.sh

#k8s-dashboard: @ Install k8s dashboard
k8s-dashboard:
	./scripts/kind-add-dashboard.sh

#nginx-ingress: @ Install Nginx ingress
nginx-ingress:
	./scripts/kind-add-ingress-nginx.sh

#metallb: @ Install MetalLB load balancer
metallb:
	./scripts/kind-add-metallb.sh

#deploy-app-nginx-ingress-localhost: @ Deploy httpd web server and create an ingress rule for a localhost (http://demo.localdev.me:80/), Patch ingress-nginx-controller service type -> LoadBlancer
deploy-app-nginx-ingress-localhost:
	./scripts/kind-deploy-app-nginx-ingress-localhost.sh

#deploy-app-helloweb: @ Deploy helloweb
deploy-app-helloweb:
	./scripts/kind-deploy-app-helloweb.sh

#deploy-app-golang-hello-world-web: @ Deploy golang-hello-world-web app
deploy-app-golang-hello-world-web:
	./scripts/kind-deploy-app-golang-hello-world-web.sh

#deploy-app-foo-bar-service: @ Deploy foo-bar-service app
deploy-app-foo-bar-service:
	./scripts/kind-deploy-app-foo-bar-service.sh

build-kubectl-test-image:
	docker build -f ./images/Dockerfile -t kubectl-test  .

#delete-cluster: @ Delete K8s cluster
delete-cluster:
	./scripts/kind-delete.sh
