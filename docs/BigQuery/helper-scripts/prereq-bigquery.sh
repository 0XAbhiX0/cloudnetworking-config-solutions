#!/bin/bash
# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
if [ -z "$GOOGLE_CLOUD_PROJECT" ]; then
    echo "Project not set!"
    echo "What project do you want to deploy the solution to?"
    read -r var_project_id
    gcloud config set project "$var_project_id"
    export GOOGLE_CLOUD_PROJECT=$var_project_id
fi

echo "Running prerequisites on project $GOOGLE_CLOUD_PROJECT for the complete BigQuery setup."
BUCKET_NAME_BQ=$GOOGLE_CLOUD_PROJECT-tf-state-bq-producer
if gsutil ls "gs://$BUCKET_NAME_BQ"; then
    echo "Terraform bucket gs://$BUCKET_NAME_BQ already created!"
else
    echo "Creating Terraform state bucket gs://$BUCKET_NAME_BQ..."
    gcloud storage buckets create "gs://$BUCKET_NAME_BQ" --project="$GOOGLE_CLOUD_PROJECT" --uniform-bucket-level-access
fi

# Create provider.tf for each stage with a unique GCS prefix
echo "Generating Terraform backend configurations..."
# NOTE: This script assumes the corresponding Terraform code exists in these directories.

# Stage 01: Organization
mkdir -p execution/01-organization
cat > execution/01-organization/providers.tf << EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME_BQ"
    prefix  = "bq_01_organization_stage"
  }
}
EOF

# Stage 02: Networking
mkdir -p execution/02-networking
cat > execution/02-networking/providers.tf << EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME_BQ"
    prefix  = "bq_02_networking_stage"
  }
}
EOF

# Stage 04: BigQuery Producer
mkdir -p execution/04-producer/BigQuery
cat > execution/04-producer/BigQuery/providers.tf << EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME_BQ"
    prefix  = "bq_04_producer_stage"
  }
}
EOF

# Stage 06: Consumer GCE
mkdir -p execution/06-consumer/GCE
cat > execution/06-consumer/GCE/providers.tf << EOF
terraform {
  backend "gcs" {
    bucket  = "$BUCKET_NAME_BQ"
    prefix  = "bq_06_consumer_gce_stage"
  }
}
EOF

echo "Enabling required APIs..."
gcloud services enable cloudbuild.googleapis.com \
    cloudresourcemanager.googleapis.com \
    iam.googleapis.com \
    logging.googleapis.com \
    storage.googleapis.com \
    compute.googleapis.com \
    serviceusage.googleapis.com \
    bigquery.googleapis.com \
    bigqueryconnection.googleapis.com --project="$GOOGLE_CLOUD_PROJECT"

echo "Granting Cloud Build's Service Account necessary IAM roles..."
PROJECT_NUMBER=$(gcloud projects describe "$GOOGLE_CLOUD_PROJECT" --format='value(projectNumber)')
CLOUDBUILD_SA="$PROJECT_NUMBER@cloudbuild.gserviceaccount.com"

# Grant roles necessary for Cloud Build to execute the full stack deployment.
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/bigquery.admin" --condition=None
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/storage.admin" --condition=None
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/serviceusage.serviceUsageAdmin" --condition=None
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/iam.serviceAccountUser" --condition=None
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/compute.networkAdmin" --condition=None
gcloud projects add-iam-policy-binding "$GOOGLE_CLOUD_PROJECT" --member="serviceAccount:$CLOUDBUILD_SA" --role="roles/compute.instanceAdmin.v1" --condition=None


echo "BigQuery Prerequisites script for complete setup finished successfully!"