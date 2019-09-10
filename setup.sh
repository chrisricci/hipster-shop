#!/usr/bin/env bash

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

TMP="$(pwd)/tmp"
CWD=$(pwd)
PROJECT_DIR=$(pwd)
PROJECT_NAME_FILE="${PROJECT_DIR}/project-id.sh"
cd ${CWD}

#############################################
# Install GCP SDK
#############################################
install_gcp_sdk() {
	echo "Prepare to install GCP SDK..."
	export CLOUD_SDK_REPO="cloud-sdk-$(lsb_release -c -s)"
	echo "deb https://packages.cloud.google.com/apt $CLOUD_SDK_REPO main" | \
	        sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

	curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

	echo "Install GCP SDK..."
	sudo apt-get update && sudo apt-get install google-cloud-sdk

  echo "Install additional components into development environment..."
  sudo apt-get update && sudo apt-get --only-upgrade install \
      google-cloud-sdk \
      google-cloud-sdk-pubsub-emulator
}

############################################################################
# Install requisite software
############################################################################
install () {
  mkdir -p ${TMP}
  INSTALL_FLAG=${TMP}/install.marker
  if [ -f "$INSTALL_FLAG" ]; then
      echo "File '$INSTALL_FLAG' was found = > no need to do the install since it already has been done."
      return
  fi

  if which sw_vers; then
      echo "Seems we are on MAC OS, fancy eh..."
      brew install gpg
      if which gcloud; then
          echo "gcloud is already installed"
      else
          echo "Please install and configure gcloud SDK as described here: https://cloud.google.com/sdk/docs/quickstart-macos"
          exit 1
      fi
  else
      lsb_release -a
      echo "Linux it is, fasten your seatbelts..."
      yes | sudo apt-get update
      yes | sudo apt-get --assume-yes install bc
      yes | sudo apt-get install apt-transport-https unzip zip rng-tools
      echo "Checking whether we need to install gcloud..."
      command -v gcloud >/dev/null 2>&1 || { echo >&2 "'gcloud' is not installed."; install_gcp_sdk ; }
  fi

  if which kubectl; then
      echo "'kubectl' is already installed"
  else
      echo "Installing kubectl"
      gcloud components install kubectl
  fi

  if which docker; then
      echo "'docker' is already installed"
  else
      echo "Please install and configure 'Docker Desktop' as described here: https://docs.docker.com/docker-for-mac/kubernetes"
      exit 1
  fi

  if which skaffold; then
      echo "'skaffold' is already installed"
  else
      echo "Installing 'skaffold' as described here: https://skaffold.dev/docs/getting-started"
      brew install skaffold
      ### Alternative method of install
      #curl -Lo skaffold  https://storage.googleapis.com/skaffold/releases/latest/skaffold-darwin-amd64
      #chmod +x skaffold
      #sudo mv skaffold /usr/local/bin
  fi

  if which kind; then
      echo "'kind' is already installed"
  else
      echo "Installing Kubernetes in Docker... (ehh, never mind - skipping this...)"
      ### Docker for Desktop works just fine while KIND has an issue with Load Balancer, hence skip this
      #echo "Install KIND..."
      #GO111MODULE="on" go get sigs.k8s.io/kind@v0.4.0
      #echo "Creating new KIND k8s cluster..."
      #kind create cluster
  fi

  touch $INSTALL_FLAG
}

##################################################################################
# Save project ID into a file
# Input:
#   1 - Project ID
##################################################################################
save_project_id() {
  local PROJECT_ID=$1

  if [ -f $PROJECT_NAME_FILE ] ; then
    local NOW=$(date +%Y-%m-%d.%H:%M:%S)
    mv $PROJECT_NAME_FILE ${PROJECT_NAME_FILE}.$NOW
  fi

  echo "export PROJECT=$PROJECT_ID" > ${PROJECT_NAME_FILE}
  echo "export GKE_KUBE_CONTEXT=tbd" >> ${PROJECT_NAME_FILE}
}

##################################################################################
# This is only valid on MAC
##################################################################################
if which sw_vers; then
  echo "MAC OS found"
  function sha256sum() { shasum -a 256 "$@" ; } && export -f sha256sum
fi

##################################################################################
# Generate random project ID
##################################################################################
generate_project_id() {
  echo "hipster-shop-$(date +%s | sha256sum | base64 | head -c 4)" | tr '[:upper:]' '[:lower:]'
}

#############################################
# Ask user if he wants a new project or not
# Returns:
#   TRUE - if user wants to create new project
#   FALSE - if user does not want to create new project
#############################################
ask_create_project() {
  if gcloud projects list | grep -q $PROJECT; then
    # If project already exists, no need to create it
    echo "false"
  else
    read -p "********************** Do you want to create new project named '$PROJECT'? (y/n)" choice
    case "$choice" in
      y|Y ) echo "true";;
      n|N ) echo "false";;
      * ) echo "false";;
    esac
  fi
}

#############################################
# Create new project in GCP
#############################################
create_project() {
  echo "Creating new project '$PROJECT'..."
  PROJECT_JSON_REQUEST=project.json
  echo "Creating JSON request file $TMP/$PROJECT_JSON_REQUEST..."

  if [ ! -d "$TMP" ]; then
  mkdir $TMP
  fi

  if [ -f "$TMP/$PROJECT_JSON_REQUEST" ]; then
    rm -f $TMP/$PROJECT_JSON_REQUEST
  fi

  cat << EOF > $TMP/$PROJECT_JSON_REQUEST
{
    "projectId": "$PROJECT",
    "name": "$PROJECT project",
    "parent": {
        id: "$PARENT_FOLDER",
        type: "folder"
    },
    "labels": {
      "environment": "development"
    }
}
EOF

  echo "Obtaining ACCESS_TOKEN for service []account..."
  ACCESS_TOKEN=$(gcloud auth print-access-token)

  echo "Creating new project '$PROJECT'..."
  GOOGLE_API_URL="https://cloudresourcemanager.googleapis.com/v1/projects/"
  curl -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $ACCESS_TOKEN" -d @${TMP}/${PROJECT_JSON_REQUEST} ${GOOGLE_API_URL}

  # Check if project is created before moving on
  i="0"
  while [ $i -lt 5 ]
  do
      if gcloud projects list | grep -q $PROJECT; then
           echo "Project '$PROJECT' has been found."
           break
      else
           echo "Waiting on Project '$PROJECT' creation to finish..."
           ((i+=1))
           sleep 5s
           # If after 30 seconds project is not found then exit script
           if [ $i -eq 5 ]; then
                echo "ERROR: Project '$PROJECT' not created in time, script will exit now, please check for errors in project creation!"
                exit 1
           fi
      fi
  done
  gcloud alpha billing projects link $PROJECT --billing-account $BILLING_ACCOUNT_ID
}

#############################################
# Enable APIs for the project
#############################################
enable_project_apis() {
  echo_my "Enabling APIs on the project..."
  gcloud services enable \
        container.googleapis.com \
        containerregistry.googleapis.com \
        cloudtrace.googleapis.com \
        cloudbuild.googleapis.com \
        containerscanning.googleapis.com \
        sourcerepo.googleapis.com \
        containeranalysis.googleapis.com \
        binaryauthorization.googleapis.com \
        cloudkms.googleapis.com \
        cloudresourcemanager.googleapis.com \
        storage-component.googleapis.com
}

#############################################
# GKE cluster creation
#############################################
create_cluster() {
  if ! gcloud container clusters describe ${CLUSTER_NAME} &> /dev/null ; then
      echo_my "create_cluster: Creating a '${CLUSTER_NAME}' GKE cluster..."
      gcloud beta container clusters create ${CLUSTER_NAME} \
          --cluster-version=latest \
          --enable-autoupgrade \
          --enable-autoscaling \
          --enable-binauthz \
          --min-nodes=3 \
          --max-nodes=10 \
          --num-nodes=5 \
          --zone=${ZONE}
  else
       echo_my "create_cluster: Cluster '${CLUSTER_NAME}' has been found"
  fi
}

#############################################
# Setup and prep local repo - need this since triggers for build can only be with local repo
#############################################
create_repo() {
  if ! gcloud source repos describe ${SOURCE_REPOSITORY} &> /dev/null ; then
      echo_my "Creating source repo '${SOURCE_REPOSITORY}' in the local project..."
      gcloud source repos create ${SOURCE_REPOSITORY} --project=${PROJECT}
  else
       echo_my "Repo '${SOURCE_REPOSITORY}' has been found"
  fi

  echo_my "Push code into the new source repo..."
  REMOTE_NAME="remote-${PROJECT}"
  git remote add ${REMOTE_NAME} https://source.developers.google.com/p/${PROJECT}/r/${SOURCE_REPOSITORY} | true # ignore if the repo has already been added
  git push ${REMOTE_NAME}
}

############################################################################
# MAIN
############################################################################
echo "#################################################"
echo "     Starting the project setup process..."
echo "#################################################"

install

# Have we been provided with the project ID as command line parameter?
if [[ $# -eq 1 ]]; then
    PROJECT=$1
    save_project_id $PROJECT
else
    if [ -f $PROJECT_NAME_FILE ] ; then
        source $PROJECT_NAME_FILE
    else
        save_project_id $(generate_project_id)
    fi
fi

# If there is not an environment file yet in the home directory of the user - make a copy
if ! [ -f ${PROJECT_DIR}/setenv-local.sh ] ; then
    cp template-setenv-local.sh ${PROJECT_DIR}/setenv-local.sh
fi
source setenv.sh

echo_my "Setup default region and zone..."
gcloud config set compute/region $REGION
gcloud config set compute/zone $ZONE

if $(ask_create_project) ; then create_project; fi
echo_my "Setup default project..."
gcloud config set project $PROJECT

enable_project_apis

create_repo

create_cluster

echo_my "Enable docker CLI to authenticate to GCR..."
gcloud auth configure-docker

echo_my "Get cluster credentials..."
gcloud container clusters get-credentials ${CLUSTER_NAME}

echo_my "Set context and namespace..."
GKE_KUBE_CONTEXT=$(kubectl config get-contexts --no-headers=true --output="name" | grep ${PROJECT} |
                    grep ${CLUSTER_NAME})

echo "export GKE_KUBE_CONTEXT=${GKE_KUBE_CONTEXT}" >> ${PROJECT_NAME_FILE}

echo "#################################################"
echo "              Project setup complete"
echo "#################################################"