#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# dashboard 
# https://github.com/kubernetes/dashboard
# https://upcloud.com/resources/tutorials/deploy-kubernetes-dashboard
# https://www.containiq.com/post/intro-to-kubernetes-dashboards
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.1/aio/deploy/recommended.yaml
kubectl apply -f ./k8s/dashboard-admin.yaml
# kubectl describe serviceaccount admin-user -n kubernetes-dashboard
# kubectl describe secret admin-user-token -n kubernetes-dashboard

# dashboard_admin_token=$(kubectl get secret -n kubernetes-dashboard $(kubectl get serviceaccount admin-user -n kubernetes-dashboard -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode)
# export dashboard_admin_token=$(kubectl -n kubernetes-dashboard create token admin-user)
export dashboard_admin_token=$(kubectl get secret -n kubernetes-dashboard admin-user-token -o jsonpath="{.data.token}" | base64 --decode)
echo "${dashboard_admin_token}" > dashboard-admin-token.txt
kubectl config set-credentials cluster-admin --token=${dashboard_admin_token}
echo "Dashboard Token: ${dashboard_admin_token}"

cd $LAUNCH_DIR