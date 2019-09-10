#!/usr/bin/env bash

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

if [ -z ${1+x} ]
then
   OPERATION="run"
else
  case "$1" in
    build | dev | run | delete ) OPERATION=$1 ;;
    * ) echo "Operation '${1}' is invalid. It must be a valid skaffold operation, such as 'build | run | dev'" && exit
    1 ;;
  esac
fi

source setenv.sh

print_header "Deploy into k8s cluster..."

echo_my "Setup skaffold config..."
skaffold config set --global local-cluster ${LOCAL_CLUSTER}

skaffold ${OPERATION}  --filename="skaffold-no-load.yaml" \
              --kube-context="${KUBE_CONTEXT}" \
              ${DEFAULT_REPO}

print_footer "Deployment completed OK..."