#!/usr/bin/env bash

echo "setenv.sh: start..."

command -v bc >/dev/null 2>&1 || { echo >&2 "'bc' is not installed."; yes | sudo apt-get --assume-yes install bc; }

### This is the path to the home directory of the project
PROJECT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "Project directory is set to PROJECT_DIR='$PROJECT_DIR'"

source ${PROJECT_DIR}/setenv-local.sh

echo "Deployment target: '${DEPLOY_TARGET}'"
case "${DEPLOY_TARGET}" in
  ${GKE_DEPLOY})
      KUBE_CONTEXT="${GKE_KUBE_CONTEXT}"
      LOCAL_CLUSTER="false"
      DEFAULT_REPO="--default-repo=gcr.io/${PROJECT}"
      ;;
  ${LOCAL_DEPLOY})
      KUBE_CONTEXT="${LOCAL_KUBE_CONTEXT}"
      LOCAL_CLUSTER="true"
      DEFAULT_REPO="--default-repo="
      ;;
  *)
      echo "DEPLOY_TARGET is not set - please set it to the valid value"
      exit 1
      ;;
esac

ATTESTOR="security_signer"
PASSPHRASE="password"
SOURCE_REPOSITORY="hipster"
NAMESPACE="default"

echo "KUBE_CONTEXT='$KUBE_CONTEXT'"
echo "NAMESPACE='$NAMESPACE'"
echo "LOCAL_CLUSTER='$LOCAL_CLUSTER'"
echo "DEFAULT_REPO='$DEFAULT_REPO'"
echo "PROJECT='$PROJECT'"

kubectl config set-context ${KUBE_CONTEXT} --namespace=${NAMESPACE}
kubectl config use-context ${KUBE_CONTEXT}

###############################################
# Wait for user input
###############################################
pause ()
{
	read -p "Press Enter to continue or Ctrl-C to stop..."
}

###############################################
# Fail processing
###############################################
die()
{
	echo Error: $?
	exit 1
}

###############################################
# Fail processing
# Input - any text
###############################################
log_error()
{
	echo "Error: $?. Details: $1" >> errors.log
	exit 1
}

###############################################
# Starts measurements of time
###############################################
start_timer()
{
	START_TIME=$(date +%s)
}

###############################################
# Stop timer and write data into the log file
###############################################
measure_timer()
{
  if [ -z ${START_TIME+x} ]; then
    MEASURED_TIME=0
  else
    END_TIME=$(date +%s)
    local TIMER=$(echo "$END_TIME - $START_TIME" | bc)
    MEASURED_TIME=$(printf "%.2f\n" $TIMER)
  fi
}

###############################################
# Print starting headlines of the scrit
# Params:
#	1 - text to show
###############################################
SEPARATOR="*************************************************************************"
CALLER="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"
COLOR='\033[32m'
NORMAL='\033[0m'
print_header()
{
	start_timer
	printf "\n${COLOR}$SEPARATOR${NORMAL}"
	printf "\n${COLOR}STARTED: $1 ($CALLER)${NORMAL}"
	printf "\n${COLOR}$SEPARATOR${NORMAL}\n"
}

###############################################
# Print closing footer of the scrit
###############################################
print_footer()
{
	measure_timer
	printf "\n${COLOR}$SEPARATOR${NORMAL}"
	printf "\n${COLOR}$1${NORMAL}"
	printf "\n${COLOR}FINISHED: in $MEASURED_TIME seconds ($CALLER).${NORMAL}"
	printf "\n${COLOR}$SEPARATOR${NORMAL}\n"
}

##############################################################################
# Replace standard ECHO function with custom output
# PARAMS:		1 - Text to show (mandatory)
# 				2 - Logging level (optional) - see levels below
##############################################################################
# Available logging levels (least to most verbose)
ECHO_NONE=0
ECHO_NO_PREFIX=1
ECHO_ERROR=2
ECHO_WARNING=3
ECHO_INFO=4
ECHO_DEBUG=5
# Default logging level
ECHO_LEVEL=$ECHO_DEBUG

echo_my()
{
	local RED='\033[0;31m'
	local GREEN='\033[32m'
	local ORANGE='\033[33m'
	local NORMAL='\033[0m'
	local PREFIX="$CALLER->"

	if [ $# -gt 1 ]; then
		local ECHO_REQUESTED=$2
	else
		local ECHO_REQUESTED=$ECHO_INFO
	fi

	if [ $ECHO_REQUESTED -gt $ECHO_LEVEL ]; then return; fi
	if [ $ECHO_REQUESTED = $ECHO_NONE ]; then return; fi
	if [ $ECHO_REQUESTED = $ECHO_ERROR ]; then PREFIX="${RED}[ERROR] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_WARNING ]; then PREFIX="${RED}[WARNING] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_INFO ]; then PREFIX="${GREEN}[INFO] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_DEBUG ]; then PREFIX="${ORANGE}[DEBUG] ${PREFIX}"; fi
	if [ $ECHO_REQUESTED = $ECHO_NO_PREFIX ]; then PREFIX="${GREEN}"; fi

  measure_timer
	printf "${PREFIX}$1 ($MEASURED_TIME seconds)${NORMAL}\n"
}

echo "setenv.sh: done"