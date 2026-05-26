# Integration & Deployment Guide

Complete step-by-step guide to deploying the HRM GitOps Platform from scratch.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Bootstrap — Run Once Locally](#2-bootstrap--run-once-locally)
3. [Workload Identity Federation Setup](#3-workload-identity-federation-setup)
4. [GitHub Repository Setup](#4-github-repository-setup)
5. [IAP OAuth Client Setup](#5-iap-oauth-client-setup)
6. [Pipeline Variables and Secrets](#6-pipeline-variables-and-secrets)
7. [First Deployment](#7-first-deployment)
8. [Post-Deploy Steps](#8-post-deploy-steps)
9. [Destroy](#9-destroy)

---

## 1. Prerequisites

### Local tools

```bash
gcloud --version        # >= 450.0.0
terraform --version     # >= 1.5.0
terragrunt --version    # >= 0.55.0
kubectl version         # >= 1.28
```

### GCP Project

1. Create a GCP project or use an existing one
2. Enable billing on the project
3. Authenticate locally:

```bash
gcloud auth login
gcloud auth application-default login
gcloud config set project YOUR_PROJECT_ID
export GOOGLE_CLOUD_PROJECT=YOUR_PROJECT_ID
```

---

## 2. Bootstrap — Run Once Locally

The bootstrap layer creates the GCS state bucket, enables all required APIs, and
provisions the Workload Identity Federation pool and CI/CD service account. This must
be run **before** the CI/CD pipeline can function.

```bash
cd global/bootstrap
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID"
terraform apply -var="project_id=YOUR_PROJECT_ID"
```

**What this creates:**
- GCS state bucket: `dev-state-bucket-project-YOUR_PROJECT_ID`
- WIF pool: `github-actions-pool`
- WIF provider: `github-provider` (trusts `token.actions.githubusercontent.com`, scoped to this repo only)
- CI/CD Service Account: `github-actions-tf-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com`
- All required GCP APIs enabled (Compute, GKE, Cloud SQL, IAM, Secret Manager, etc.)

**Read the outputs — you will need these for GitHub secrets and variables:**
```bash
terraform output workload_identity_provider   # → GOOGLE_WIF_PROVIDER secret
terraform output cicd_sa_email               # → GOOGLE_SA_EMAIL secret
terraform output state_bucket_name           # → STATE_BUCKET variable
```

Bootstrap manages its own state locally. Do not delete the `terraform.tfstate`
file in `global/bootstrap/` — it is needed to modify or destroy bootstrap resources.

> **Re-apply bootstrap after any change to `wif.tf` or `api.tf`** using your personal
> credentials, not the CI/CD pipeline.

---

## 3. Workload Identity Federation Setup

WIF allows GitHub Actions to authenticate to GCP without storing JSON key files.
The bootstrap step already created the pool and provider. This section explains
how it works and what values you need.

### How it works

```
GitHub Actions generates a short-lived OIDC JWT token
    ↓
Token sent to GCP STS (Security Token Service)
    ↓
WIF Pool validates token against token.actions.githubusercontent.com
    ↓
Attribute condition checked: assertion.repository == 'Y3GI/high_availability_hrm'
    ↓
GCP issues a short-lived access token for the CI/CD SA (1 hour expiry)
    ↓
Pipeline uses token for all GCP API calls — no stored credentials
```

The attribute condition scopes trust to this specific repository.
A fork of the repo cannot use your WIF pool.

### The `GOOGLE_WIF_PROVIDER` value

Format:
```
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-actions-pool/providers/github-provider
```

This uses the **project number** (numeric), not the project ID string.

Get both values:
```bash
# Project number
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"

# Or get the full string directly from bootstrap output
cd global/bootstrap
terraform output workload_identity_provider
```

---

## 4. GitHub Repository Setup

### Actions permissions

```
GitHub → Settings → Actions → General:
    ✅ Read and write permissions  (Workflow permissions)
    ✅ Allow GitHub Actions to create and approve pull requests
```

### Branch protection (recommended)

```
GitHub → Settings → Branches → Add rule for "main":
    ✅ Require status checks to pass before merging
    ✅ Require branches to be up to date before merging
```

---

## 5. IAP OAuth Client Setup

Google shut down the IAP OAuth Admin API in March 2026. The OAuth brand and client
**cannot be created via Terraform** — this is a one-time manual step in the GCP Console.

### Step 1 — Configure the OAuth consent screen

```
GCP Console → APIs & Services → OAuth consent screen
    User type: External
    App name: HRM Onboarding Platform
    User support email: your-email@example.com
    Authorized domain: duckdns.org
    Developer contact: your-email@example.com
→ Save and Continue through all steps
```

### Step 2 — Create an OAuth 2.0 Client ID

```
GCP Console → APIs & Services → Credentials
    → Create credentials → OAuth 2.0 Client ID
    Application type: Web application
    Name: HRM IAP Client
→ Create
```

Copy the **Client ID** and **Client Secret** — they are shown only once.

### Step 3 — Add IAP redirect URI

In the OAuth client settings, add the following to **Authorised redirect URIs**:

```
https://iap.googleapis.com/v1/oauth/clientIds/YOUR_CLIENT_ID:handleRedirect
```

Replace `YOUR_CLIENT_ID` with the client ID from step 2.

### Step 4 — Store as GitHub secrets

Add both values in `GitHub → Settings → Secrets and variables → Actions`:

| Secret Name | Value |
|---|---|
| `IAP_CLIENT_ID` | The Client ID from step 2 |
| `IAP_CLIENT_SECRET` | The Client Secret from step 2 |

The CI/CD pipeline reads these secrets directly when creating the `iap-oauth-secret`
Kubernetes secret in the `hrm` namespace. They are never written to Terraform state.

---

## 6. Pipeline Variables and Secrets

Configure all remaining values in `GitHub → Settings → Secrets and variables → Actions`.

### Secrets (encrypted, never visible after saving)

| Secret Name | Value | Source |
|---|---|---|
| `GOOGLE_WIF_PROVIDER` | WIF provider resource name | `terraform output workload_identity_provider` in `global/bootstrap` |
| `GOOGLE_SA_EMAIL` | CI/CD SA email | `terraform output cicd_sa_email` in `global/bootstrap` |
| `IAP_CLIENT_ID` | IAP OAuth client ID | GCP Console — see Section 5 |
| `IAP_CLIENT_SECRET` | IAP OAuth client secret | GCP Console — see Section 5 |
| `SESSION_SECRET` | Random string ≥ 32 chars for signing workspace session cookies | Generate: `python3 -c "import secrets; print(secrets.token_hex(32))"` |

### Variables (non-sensitive configuration)

| Variable Name | Example Value | Description |
|---|---|---|
| `GOOGLE_REGION` | `europe-west4` | GCP region — must match root `terragrunt.hcl` |
| `GOOGLE_CLOUD_PROJECT` | `my-project-id` | GCP project ID — used by `get_env()` in Terragrunt |
| `STATE_BUCKET` | `dev-state-bucket-project-my-project-id` | GCS bucket name — must match bootstrap output exactly |
| `ENV_NAME` | `dev` | Environment name — must match `env` local in root `terragrunt.hcl` |
| `CLUSTER_NAME` | `dev-gke-cluster` | GKE cluster name — format: `${ENV_NAME}-gke-cluster` |

---

## 7. First Deployment

### Step 1 — Trigger the deploy pipeline

```bash
git add .
git commit -m "feat: initial platform deployment"
git push origin main
```

### Step 2 — What the deploy pipeline does

The `terraform_deploy.yml` pipeline runs three jobs:

**Job 1 — Terragrunt Apply** (runs first):
```
1. Authenticate to GCP via WIF (no stored credentials)
2. terragrunt run-all plan  — validates all modules
3. terragrunt run-all apply — provisions infrastructure in DAG order:
       networking → gke → storage → security → functions → monitoring
```

**Job 2 — Push Workspace Images** (after Job 1, parallel with Job 3):
```
4. Pull codercom/code-server:latest
5. Retag and push to Artifact Registry for each department:
       software-workspace, devops-workspace, db-engineering-workspace
6. Build HRM app image from hrm_app/ and push with git SHA tag
```

**Job 3 — Configure Cluster** (after Job 1, parallel with Job 2):
```
7.  Get GKE cluster credentials
8.  Install ArgoCD in argocd namespace (idempotent — skips if already installed)
9.  Apply ArgoCD AppProject + Application manifests
10. Read Terraform outputs: app SA email, Cloud SQL connection name, Cloud Function URL
11. Generate k8s/apps/hrm/values.yaml from values.yaml.tpl via envsubst
12. Generate department serviceaccount.yaml files from .tpl files via envsubst
13. Create iap-oauth-secret in hrm namespace
14. Create hrm-db-secret in hrm namespace
15. Create hrm-session-secret in hrm namespace (from SESSION_SECRET GitHub secret)
16. Commit generated manifests back to repo [skip ci]
```

ArgoCD takes over after step 16 and syncs all manifests into the cluster.

**Expected duration:** 20–30 minutes on first run (Cloud SQL HA provisioning is the
slowest step at ~10 minutes).

### Step 3 — Verify

```bash
# Get cluster credentials locally
gcloud container clusters get-credentials dev-gke-cluster \
  --region europe-west4 \
  --project YOUR_PROJECT_ID

# Check all ArgoCD applications are Synced + Healthy
kubectl get applications -n argocd

# Check pods across all namespaces
kubectl get pods -A

# Get ArgoCD UI password
kubectl get secret argocd-initial-admin-secret \
  -n argocd \
  -o jsonpath="{.data.password}" | base64 --decode
```

---

## 8. Post-Deploy Steps

### 8.1 GitHub PAT Setup

The Cloud Function commits workspace manifests to this repository on behalf of HR.
It authenticates using a GitHub Personal Access Token stored in GCP Secret Manager.
The token is **never stored in code or pipeline variables**.

#### Create the PAT

1. Go to `GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens`
2. Click **Generate new token**
3. Configure:
   - **Token name:** `hrm-cloud-function`
   - **Expiration:** 90 days (renew before expiry or workspace provisioning will fail)
   - **Repository access:** Only select repositories → choose this repo
   - **Permissions:**
     - `Contents: Read and Write` — required to commit workspace manifests
     - `Metadata: Read` — required by default
4. Click **Generate token** — copy the value immediately, it is shown only once

#### Store the PAT in Secret Manager

Run this **after** the first `terraform apply` has completed (which creates the secret resource):

```bash
echo -n "YOUR_GITHUB_PAT_VALUE" | gcloud secrets versions add dev-github-token \
  --data-file=- \
  --project=YOUR_PROJECT_ID
```

Verify:
```bash
gcloud secrets versions access latest \
  --secret=dev-github-token \
  --project=YOUR_PROJECT_ID
```

The Cloud Function reads this secret at runtime via its Workload Identity SA.
Without this the Cloud Function will fail to commit workspace manifests.

### 8.2 Configure DNS

Get the reserved load balancer IP:
```bash
cd env/dev/security
terragrunt output ingress_ip
```

Log in to [duckdns.org](https://www.duckdns.org) and set the IP for your subdomain:
```
cs3-hrm-app.duckdns.org → LOAD_BALANCER_IP
```

The GCP-managed SSL certificate activates automatically within 10–20 minutes of
DNS propagation. Certificate provisioning requires the domain to resolve correctly
— do not skip this step if you want HTTPS.

### 8.3 Add your account to IAP

After deployment, grant yourself (and any other HR admins) access to the HRM app:

```bash
gcloud iap web add-iam-policy-binding \
  --resource-type=backend-services \
  --service=YOUR_BACKEND_SERVICE_ID \
  --member="user:your-email@example.com" \
  --role="roles/iap.httpsResourceAccessor" \
  --project=YOUR_PROJECT_ID
```

Or manage `iap_members` in `env/dev/terragrunt.hcl` and re-apply.

### 8.4 Verify monitoring

Navigate to `GCP Console → Monitoring → Dashboards` to confirm the HRM Platform
dashboard was created. Alert policies are visible under `Monitoring → Alerting`.

The uptime check pings `https://cs3-hrm-app.duckdns.org/api/health` every 60 seconds.
It will show failures until DNS and the SSL certificate are configured.

---

## 9. Destroy

Destroy is intentionally manual and requires explicit confirmation.

```
GitHub → Actions → Destroy Workflow → Run workflow → type "Destroy" → Run
```

**What the destroy pipeline does:**
1. Authenticates to GCP via WIF
2. Runs `terragrunt run-all destroy` across all modules

**What is NOT destroyed automatically:**
- The GCS state bucket (created by bootstrap, not managed by env/dev Terragrunt)
- The WIF pool and CI/CD SA (created by bootstrap)
- Bootstrap local state file
- IAP OAuth client and consent screen (created manually)

To fully clean up:
```bash
# Remove state bucket
gsutil rm -r gs://dev-state-bucket-project-YOUR_PROJECT_ID

# Destroy bootstrap resources
cd global/bootstrap
terraform destroy -var="project_id=YOUR_PROJECT_ID"
```

**Warning:** Destroying Cloud SQL removes all data. Ensure backups are taken first
if the database contains data you need.
