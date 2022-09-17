#help: @ List available tasks
help: ll: @clear ./scripts/kind-install-all.sh @echo "Usage: make COMMAND" @echo "Commands :"@create-cluster: ./scripts/kind-create.sh
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-19s\033[0m - %s\n", $$1, $$2}'

@export-cert:
	./scripts/kind-export-cert.sh

@k8s-dashboard:
	./scripts/kind-add-dashboard.sh

@nginx-ingress:
	./scripts/kind-add-ingress-nginx.sh

@metallb:
	./scripts/kind-add-metallb.sh

@deploy-app-nginx-ingress-localhost:
	./scripts/kind-deploy-app-nginx-ingress-localhost.sh

@deploy-app-helloweb:
	./scripts/kind-deploy-app-helloweb.sh

@deploy-app-golang-hello-world-web:
	./scripts/kind-deploy-app-golang-hello-world-web.sh

@deploy-app-foo-bar-service:
	./scripts/kind-deploy-app-foo-bar-service.sh
