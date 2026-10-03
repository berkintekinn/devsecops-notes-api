#!/usr/bin/env bash
# One-time GCP setup: Artifact Registry + keyless (OIDC) deploy from GitHub Actions.
# usage: ./deploy/setup-gcp.sh <gcp-project-id> <github-owner/repo> [region]
set -euo pipefail

PROJECT_ID="$1"
REPO="$2"
REGION="${3:-europe-west1}"
SA_NAME="gh-deployer"
SA="$SA_NAME@$PROJECT_ID.iam.gserviceaccount.com"
POOL="github"
PROVIDER="github-oidc"

gcloud config set project "$PROJECT_ID"
gcloud services enable run.googleapis.com artifactregistry.googleapis.com iamcredentials.googleapis.com

gcloud artifacts repositories create apps --repository-format=docker --location="$REGION" || true

gcloud iam service-accounts create "$SA_NAME" --display-name="GitHub Actions deployer" || true
for role in roles/run.admin roles/artifactregistry.writer roles/iam.serviceAccountUser; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" --member="serviceAccount:$SA" --role="$role" --condition=None >/dev/null
done

gcloud iam workload-identity-pools create "$POOL" --location=global --display-name="GitHub" || true
# only tokens issued for this exact repo, main branch, can use the provider
gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
  --location=global --workload-identity-pool="$POOL" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition="assertion.repository=='$REPO' && assertion.ref=='refs/heads/main'" || true

POOL_ID=$(gcloud iam workload-identity-pools describe "$POOL" --location=global --format='value(name)')
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --role=roles/iam.workloadIdentityUser \
  --member="principalSet://iam.googleapis.com/$POOL_ID/attribute.repository/$REPO" >/dev/null

gh variable set GCP_PROJECT_ID --repo "$REPO" --body "$PROJECT_ID"
gh variable set GCP_REGION --repo "$REPO" --body "$REGION"
gh variable set GCP_DEPLOY_SA --repo "$REPO" --body "$SA"
gh variable set GCP_WIF_PROVIDER --repo "$REPO" --body "$POOL_ID/providers/$PROVIDER"

echo "done. next push to main will deploy."
