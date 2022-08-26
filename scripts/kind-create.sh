#!/bin/bash

# set -x
LAUNCH_DIR=$(pwd); SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd $SCRIPT_DIR; cd ..; SCRIPT_PARENT_DIR=$(pwd);

cd $SCRIPT_PARENT_DIR

# https://kind.sigs.k8s.io/
# https://cloudyuga.guru/hands_on_lab/kind-k8s

kind create cluster --config=./k8s/kind-config.yaml --name kind --wait 10s
docker container ls --format "table {{.Image}}\t{{.State}}\t{{.Names}}"

cd $LAUNCH_DIR