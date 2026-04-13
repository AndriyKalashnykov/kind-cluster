#!/bin/bash

# set -x
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1


CONTEXT="kind-kind"

CERTIFICATE=$(kubectl config view --raw -o json | jq -r '.users[] | select(.name == "'${CONTEXT}'") | .user."client-certificate-data"')
KEY=$(kubectl config view --raw -o json | jq -r '.users[] | select(.name == "'${CONTEXT}'") | .user."client-key-data"')
CLUSTER_CA=$(kubectl config view --raw -o json | jq -r '.clusters[] | select(.name == "'${CONTEXT}'") | .cluster."certificate-authority-data"')

echo "${CERTIFICATE}" | base64 -d > client.crt
echo "${KEY}" | base64 -d > client.key

openssl pkcs12 -export -in client.crt -inkey client.key -out client.pfx -passout pass:

echo "${CLUSTER_CA}" | base64 -d > cluster-ca.crt

