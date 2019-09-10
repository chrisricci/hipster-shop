#!/usr/bin/env bash
#
# Based on this: https://cloud.google.com/solutions/binary-auth-with-cloud-build-and-gke
#
set -u # This prevents running the script if any of the variables have not been set
set -e # Exit if error is detected during pipeline execution

source setenv.sh

print_header "Setting up binary authentication"

BEARER=$(gcloud auth print-access-token)

export PROJECT_NUMBER="$(gcloud projects describe ${PROJECT_ID} --format='get(projectNumber)')"
export CLOUD_BUILD_SA=${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com

gcloud projects add-iam-policy-binding ${PROJECT_ID} \
    --member=serviceAccount:${CLOUD_BUILD_SA} \
    --role=roles/container.developer

echo_my "Generating key. This may take some time..."
mkdir -p ~/certs
# Skip if we are on MacOS
if ! which sw_vers; then echo_my "Increase Linux entropy" && sudo rngd -s 512 -W 3600 -r /dev/urandom; fi

ATTESTOR_EMAIL=${ATTESTOR}@example.com
gpg --batch --gen-key <(
    cat <<- EOF
    Key-Type: RSA
    Key-Length: 2048
    Name-Real: ${ATTESTOR}
    Name-Email: ${ATTESTOR_EMAIL}
    Passphrase: ${PASSPHRASE}
    %commit
EOF
)

echo_my "Export the public key"
gpg --armor --export ${ATTESTOR} > ~/certs/${ATTESTOR}.asc
PUBLIC_KEY_FINGERPRINT=$(gpg --list-keys ${ATTESTOR} | sed -n '2p')

echo ${PUBLIC_KEY_FINGERPRINT} > ~/certs/${ATTESTOR}.fpr

echo_my "Export the private key"
gpg --batch --armor  --passphrase ${PASSPHRASE} --pinentry-mode loopback --export-secret-keys "${PUBLIC_KEY_FINGERPRINT}" > ~/certs/${ATTESTOR}.gpg

echo "${PASSPHRASE}" > ~/certs/${ATTESTOR}.pass

gpg --list-secret-keys | grep -B1 ${ATTESTOR} | head -n 1 | awk \
    '{print $1}' > ~/certs/${ATTESTOR}.fpr

# Create a Cloud Storage bucket to store the keys
BUCKET=${PROJECT_ID}-keys

gsutil mb gs://$BUCKET | true # Ignore error if bucket already exists
gsutil iam ch serviceAccount:$CLOUD_BUILD_SA:objectViewer gs://$BUCKET

# Create Cloud KMS Ring
export KMS_KEYRING=binauthkeyring
export KMS_KEY=binauthkey

gcloud kms keyrings create $KMS_KEYRING  --location global | true # ignore if already exists
gcloud kms keys create $KMS_KEY \
    --location=global \
    --purpose=encryption \
    --keyring=$KMS_KEYRING | true # ignore if already exists

# Allow Cloud Build SA to decrypt objects
gcloud kms keys add-iam-policy-binding $KMS_KEY \
--keyring $KMS_KEYRING \
--location global \
--member=serviceAccount:$CLOUD_BUILD_SA \
--role='roles/cloudkms.cryptoKeyDecrypter'

echo_my "Encrypt Keys"
gcloud kms encrypt \
    --plaintext-file ~/certs/${ATTESTOR}.gpg \
    --ciphertext-file ~/certs/${ATTESTOR}.gpg.enc \
    --key=$KMS_KEY \
    --keyring=$KMS_KEYRING \
    --location=global

gcloud kms encrypt \
    --plaintext-file ~/certs/${ATTESTOR}.pass \
    --ciphertext-file ~/certs/${ATTESTOR}.pass.enc \
    --key=$KMS_KEY --keyring=$KMS_KEYRING --location=global

echo_my "Upload Encrypted Keys to GCS"
gsutil cp ~/certs/*.enc gs://$BUCKET/
gsutil cp ~/certs/*.fpr gs://$BUCKET/
gsutil cp ~/certs/*.asc gs://$BUCKET/

echo_my "Configure Attestations"
cat > /tmp/${ATTESTOR}_note_payload.json << EOM
{
"name": "projects/${PROJECT_ID}/notes/${ATTESTOR}",
"attestation_authority": {
    "hint": {
    "human_readable_name": "${PROJECT_ID}-${ATTESTOR}"
    }
}
}
EOM

echo_my "Call API to create new attestor"
curl -X POST \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${BEARER}"  \
    --data-binary @/tmp/${ATTESTOR}_note_payload.json  \
    "https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes/?noteId=${ATTESTOR}"

cat > /tmp/${ATTESTOR}_iam_request.json << EOM
{
'resource': 'projects/${PROJECT_ID}/notes/${ATTESTOR}',
'policy': {
    'bindings': [
    {
        'role': 'roles/containeranalysis.notes.occurrences.viewer',
        'members': [
        'serviceAccount:${CLOUD_BUILD_SA}'
        ]
    },
    {
        'role': 'roles/containeranalysis.notes.attacher',
        'members': [
        'serviceAccount:${CLOUD_BUILD_SA}'
        ]
    }
    ]
}
}
EOM

echo_my "Create attestor policy"
curl -X POST  \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${BEARER}" \
    --data-binary @/tmp/${ATTESTOR}_iam_request.json \
    "https://containeranalysis.googleapis.com/v1beta1/projects/${PROJECT_ID}/notes/${ATTESTOR}:setIamPolicy"

echo_my "Delete old attestor"
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors delete "${ATTESTOR}" | true # ignore if does not exists

echo_my "Create GCP attestor"
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors create "${ATTESTOR}" \
    --attestation-authority-note="${ATTESTOR}" \
    --attestation-authority-note-project="${PROJECT_ID}"

echo_my "Add public keys"
gcloud --project="${PROJECT_ID}" \
    beta container binauthz attestors public-keys add \
    --attestor="${ATTESTOR}" \
    --pgp-public-key-file ~/certs/${ATTESTOR}.asc

echo_my "Add attestor policy binding"
gcloud beta container binauthz attestors add-iam-policy-binding \
    "projects/${PROJECT_ID}/attestors/${ATTESTOR}" \
    --member="serviceAccount:${CLOUD_BUILD_SA}" \
    --role=roles/binaryauthorization.attestorsVerifier

#echo_my "Enable BinAuthz for the cluster"
#gcloud beta container clusters update ${CLUSTER_NAME} --enable-binauthz --zone ${ZONE}

gcloud beta container binauthz policy export  > policy.yaml

#sed '/^clusterAdmissionRules:$/r'<(
#  echo "  ${ZONE}.${CLUSTER_NAME}:"
#  echo "    evaluationMode: REQUIRE_ATTESTATION"
#  echo "    enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG"
#  echo "    requireAttestationsBy:"
#  echo "    - projects/${PROJECT_ID}/attestors/${ATTESTOR}"
#) policy.yaml > policy-updated.yaml
#
#echo -e "globalPolicyEvaluationMode: ENABLE\n$(cat ~/policy-updated.yaml)" > ~/policy-updated.yaml

cat > policy-updated.yaml << EOM
admissionWhitelistPatterns:
- namePattern: gcr.io/google_containers/*
- namePattern: gcr.io/google-containers/*
- namePattern: k8s.gcr.io/*
- namePattern: gcr.io/stackdriver-agents/*
defaultAdmissionRule:
  evaluationMode: REQUIRE_ATTESTATION
  enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG
  requireAttestationsBy:
    - projects/${PROJECT_ID}/attestors/${ATTESTOR}
name: projects/${PROJECT_ID}/policy
EOM

echo_my "Update Bin Authz policy"
gcloud beta container binauthz policy import policy-updated.yaml

echo_my "Setting up Vulnerability Scan Checker"
rm -rf ~/binauthz_tools | true # ignore if dir does not exist
git clone https://github.com/GoogleCloudPlatform/gke-binary-auth-tools ~/binauthz_tools

cd ~/binauthz_tools
echo_my "Build Docker attestor image"
docker build -t gcr.io/${PROJECT_ID}/cloudbuild-attestor .

echo_my "Push Docker attestor image"
gcloud docker -- push gcr.io/${PROJECT_ID}/cloudbuild-attestor

# Create Recommendation Service Build Trigger
cat > /tmp/trigger.json << EOM
{
  "triggerTemplate": {
    "projectId": "${PROJECT_ID}",
    "repoName": "${SOURCE_REPOSITORY}",
    "branchName": ".*"
  },
  "description": "[Recommendation Service] Build, Check Vulnerabilities and Deploy",
  "substitutions": {
    "_COMPUTE_ZONE": "${ZONE}",
    "_PROD_CLUSTER": "${CLUSTER_NAME}",
    "_VULNZ_NOTE_ID": "${ATTESTOR}",
    "_KMS_KEYRING": "binauthkeyring",
    "_KMS_KEY": "binauthkey"
  },
  "includedFiles": [
    "src/recommendationservice/**/*"
  ],
  "filename": "src/recommendationservice/cloudbuild.yaml"
}
EOM

echo_my "Setup Git trigger"
curl -X POST  \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER}" \
        --data-binary @/tmp/trigger.json \
        "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers"

# Create Frontend Build Trigger
cat > /tmp/frontend-trigger.json << EOM
{
  "triggerTemplate": {
    "projectId": "${PROJECT_ID}",
    "repoName": "${SOURCE_REPOSITORY}",
    "branchName": ".*"
  },
  "description": "[Frontend] Build, Check Vulnerabilities and Deploy",
  "substitutions": {
    "_COMPUTE_ZONE": "${ZONE}",
    "_PROD_CLUSTER": "${CLUSTER_NAME}",
    "_VULNZ_NOTE_ID": "${ATTESTOR}",
    "_KMS_KEYRING": "binauthkeyring",
    "_KMS_KEY": "binauthkey"
  },
  "includedFiles": [
    "src/frontend/**/*"
  ],
  "filename": "src/frontend/cloudbuild.yaml"
}
EOM

curl -X POST  \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER}" \
        --data-binary @/tmp/frontend-trigger.json \
        "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers"

# Create Payment Service Build Trigger
cat > /tmp/paymentservice-trigger.json << EOM
{
  "triggerTemplate": {
    "projectId": "${PROJECT_ID}",
    "repoName": "${SOURCE_REPOSITORY}",
    "branchName": ".*"
  },
  "description": "[Payment Service] Build, Check Vulnerabilities and Deploy",
  "substitutions": {
    "_COMPUTE_ZONE": "${ZONE}",
    "_PROD_CLUSTER": "${CLUSTER_NAME}",
    "_VULNZ_NOTE_ID": "${ATTESTOR}",
    "_KMS_KEYRING": "binauthkeyring",
    "_KMS_KEY": "binauthkey"
  },
  "includedFiles": [
    "src/paymentservice/**/*"
  ],
  "filename": "src/paymentservice/cloudbuild.yaml"
}
EOM

curl -X POST  \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER}" \
        --data-binary @/tmp/paymentservice-trigger.json \
        "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/triggers"

print_footer "Binary authentication setup has completed"