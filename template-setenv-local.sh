#!/usr/bin/env bash

echo "setenv-local.sh: start..."

### Automatically generate unique project ID for the first run and save it into a file. Later read it from file
PROJECT_NAME_FILE="$PROJECT_DIR/project-id.sh"
if [ -f "$PROJECT_NAME_FILE" ] ; then
    echo "Sourcing existing project file '$PROJECT_NAME_FILE'..."
    source $PROJECT_NAME_FILE
else
    # Infer current project ID from the environment
    export PROJECT=$(gcloud config get-value project)
fi
PROJECT_ID=${PROJECT}

### This folder will host the project - you can lookup ID in the GCP Console
PARENT_FOLDER=623112070785
### Update this to your own as can be found here:
# https://pantheon.corp.google.com/billing?project=&folder=&organizationId=433637338589
BILLING_ACCOUNT_ID="01E90A-537E78-5E39B5"

### These are Region and Zone where you want to run your car controller - feel free to change as you see fit
export REGION="us-central1"
export ZONE="us-central1-f"

# All microservices to be deployed into this cluster
export CLUSTER_NAME="hipster-cluster"
#CLUSTER_NAME="cicd-demo2"

### Local desktop k8s cluster for development
LOCAL_KUBE_CONTEXT="docker-desktop"
### Possible deployment targets
LOCAL_DEPLOY="local"
GKE_DEPLOY="gke"
### Which target to use for deployment
DEPLOY_TARGET=${GKE_DEPLOY}

echo "setenv-local.sh: done"