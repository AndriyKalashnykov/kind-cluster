#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

GITHUB_URL=https://github.com/kubernetes/dashboard/releases
DASHBOARD_VERSION=$(curl -w '%{url_effective}' -I -L -s -S ${GITHUB_URL}/latest -o /dev/null | sed -e 's|.*/||')

VERSION=${1:-$DASHBOARD_VERSION}

if [ -z "$VERSION" ]; then
    echo "Provide dashboard version"
    exit 1
fi

cd $SCRIPT_PARENT_DIR

# https://github.com/kubernetes/dashboard
# https://upcloud.com/resources/tutorials/deploy-kubernetes-dashboard
# https://www.containiq.com/post/intro-to-kubernetes-dashboards
# https://rancher.com/docs/k3s/latest/en/installation/kube-dashboard/

kubectl apply -f  https://raw.githubusercontent.com/kubernetes/dashboard/${VERSION}/aio/deploy/recommended.yaml
kubectl apply -f ./k8s/dashboard-admin.yaml

# export dashboard_admin_token=$(kubectl -n kubernetes-dashboard create token admin-user)
# export dashboard_admin_token=$(kubectl -n kubernetes-dashboard describe secret admin-user-token | grep '^token')
export dashboard_admin_token=$(kubectl get secret -n kubernetes-dashboard admin-user-token -o jsonpath="{.data.token}" | base64 --decode)
echo "${dashboard_admin_token}" > dashboard-admin-token.txt
kubectl config set-credentials cluster-admin --token=${dashboard_admin_token}
echo "Dashboard Token: ${dashboard_admin_token}"

cd $LAUNCH_DIR