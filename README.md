# kind-cluster
k8s dev cluster with kind

## Install kind cluster with Nginx ingress and Metallb load balancer

```bash
./scripts/kind-with-ingress.sh

In Dashboard UI select "Token' and `Ctrl+V`
or
`cat ./dashboard-admin-token.txt|xclip -i` and `Ctrl+V` 
```

## Uninstall kind cluster

```bash
kind delete cluster
```