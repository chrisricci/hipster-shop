#!/usr/bin/env bash

set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source setenv.sh

print_header "Cleaning up binary authentication"

gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}

gcloud beta container binauthz policy import policy.yaml

echo "Deleting Keys"
BEARER=$(gcloud auth print-access-token)
#for ATTESTOR in ${SECURITY_ATTESTOR} ${QA_ATTESTOR}
#do
ATTESTOR_EMAIL=${ATTESTOR}@example.com

PUBLIC_KEY_FINGERPRINT=$(gpg --list-keys ${ATTESTOR} | sed -n '2p')

gcloud beta container binauthz attestors public-keys remove \
            ${PUBLIC_KEY_FINGERPRINT} \
            --attestor ${ATTESTOR}

curl -X DELETE \
    -H "Authorization: Bearer ${BEARER}"  \
    "https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes/${ATTESTOR}"

gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors delete "${ATTESTOR}" 

gpg --batch --pinentry-mode loopback --yes --delete-secret-and-public-key ${PUBLIC_KEY_FINGERPRINT}
#done

rm -rf ~/certs

echo "Deleting GCS Bucket"
BUCKET=${PROJECT_ID}-keys
gsutil rm -r gs://$BUCKET

rm -rf ~/binauthz_tools

print_footer "Binary authentication cleanup is complete"