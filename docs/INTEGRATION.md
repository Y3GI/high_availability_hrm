# Integration & Deployment Guide

Complete step-by-step guide to deploying the HRM GitOps Platform from scratch.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Bootstrap — Run Once Locally](#2-bootstrap--run-once-locally)
3. [Workload Identity Federation Setup](#3-workload-identity-federation-setup)
4. [GitHub Repository Setup](#4-github-repository-setup)
5. [GitHub PAT Setup](#5-github-pat-setup)
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

The bootstrap layer creates the GCS state bucket and Workload Identity Federation
pool. This must be run **before** the CI/CD pipeline can function — Terraform needs
these resources to store state and authenticate from GitHub Actions.

```bash
cd global/bootstrap
terraform init
terraform plan
terraform apply
```

**What this creates:**
- GCS state bucket: `dev-state-bucket-project-YOUR_PROJECT_ID`
- WIF pool: `github-pool`
- WIF provider: `github-provider` (trusts `token.actions.githubusercontent.com`)
- CI/CD Service Account: `dev-cicd-sa@YOUR_PROJECT_ID.iam.gserviceaccount.com`

**Read the outputs — you will need these for GitHub secrets and variables:**
```bash
terraform output workload_identity_provider   # → GOOGLE_WIF_PROVIDER secret
terraform output cicd_sa_email               # → GOOGLE_SA_EMAIL secret
terraform output state_bucket_name           # → STATE_BUCKET variable
```

Bootstrap manages its own state locally. Do not delete the `terraform.tfstate`
file in `global/bootstrap/` — it is needed to modify or destroy bootstrap resources.

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
Attribute condition checked: assertion.repository == 'YOUR_ORG/YOUR_REPO'
    ↓
GCP issues a short-lived access token for the CI/CD SA (1 hour expiry)
    ↓
Pipeline uses token for all GCP API calls — no stored credentials
```

The attribute condition scopes trust to your specific repository.
A fork of the repo cannot use your WIF pool.

### The `GOOGLE_WIF_PROVIDER` value

Format:
```
projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider
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

## 5. Pipeline Variables and Secrets

Configure in `GitHub → Settings → Secrets and variables → Actions`.

### Secrets (encrypted, never visible after saving)

| Secret Name | Value | Source |
|---|---|---|
| `GOOGLE_WIF_PROVIDER` | WIF provider resource name | `terraform output workload_identity_provider` in `global/bootstrap` |
| `GOOGLE_SA_EMAIL` | CI/CD SA email | `terraform output cicd_sa_email` in `global/bootstrap` |

### Variables (non-sensitive configuration)

| Variable Name | Example Value | Description |
|---|---|---|
| `GOOGLE_REGION` | `europe-west4` | GCP region — must match root `terragrunt.hcl` |
| `GOOGLE_CLOUD_PROJECT` | `my-project-id` | GCP project ID — used by `get_env()` in Terragrunt |
| `STATE_BUCKET` | `dev-state-bucket-project-my-project-id` | GCS bucket name — must match bootstrap output exactly |
| `ENV_NAME` | `dev` | Environment name — must match `env` local in root `terragrunt.hcl` |
| `CLUSTER_NAME` | `dev-gke-cluster` | GKE cluster name — format: `${ENV_NAME}-gke-cluster` |

---

## 6. First Deployment

### Step 1 — Trigger the deploy pipeline

```bash
git add .
git commit -m "feat: initial platform deployment"
git push origin main
```

### Step 2 — What the deploy pipeline does

```
1.  Authenticate to GCP via WIF (no stored credentials)
2.  terragrunt run-all plan  — validates all modules
3.  terragrunt run-all apply — provisions infrastructure in DAG order:
        networking → gke → storage → security → functions → monitoring
4.  Pull codercom/code-server, retag, push to Artifact Registry (3 dept images)
5.  Get GKE cluster credentials
6.  Install ArgoCD in argocd namespace (skips if already installed)
7.  Apply ArgoCD AppProject + Application manifests
8.  Read Terraform outputs (app SA email, IAP credentials, Cloud SQL connection name,
    Cloud Function URL)
9.  Generate k8s/apps/hrm/values.yaml from values.yaml.tpl via envsubst
10. Generate department serviceaccount.yaml files from .tpl files via envsubst
11. Create iap-oauth-secret in hrm namespace
12. Create hrm-db-secret in hrm namespace
13. Commit generated files back to repo [skip ci]
```

ArgoCD takes over after step 13 and syncs all manifests into the cluster.

**Expected duration:** 20–30 minutes on first run (Cloud SQL HA provisioning is the
slowest step at ~10 minutes).

### Step 3 — Build the HRM app image

The HRM app image is built by a separate workflow triggered by changes to `hrm-app/**`.
On first deployment, trigger it manually or push a small change to `hrm-app/`:

```bash
touch hrm-app/.trigger
git add hrm-app/.trigger
git commit -m "chore: trigger initial app image build"
git push origin main
```

### Step 4 — Verify

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

## 7. Post-Deploy Steps

### 7.1 GitHub PAT Setup

The Cloud Function commits workspace manifests to this repository on behalf of HR.
It authenticates using a GitHub Personal Access Token stored in GCP Secret Manager.
The token is **never stored in code or pipeline variables**.

### Create the PAT

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

### Store the PAT in Secret Manager

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

### 7.2 Configure DNS

Get the reserved load balancer IP:
```bash
cd env/dev/security
terragrunt output ingress_ip
```

Add a DNS A record at your domain registrar:
```
hrm.yourdomain.com → LOAD_BALANCER_IP
```

The GCP-managed SSL certificate activates automatically within 10–20 minutes of
DNS propagation. Certificate provisioning requires the domain to resolve correctly
— do not skip this step if you want HTTPS.

### 7.3 Verify monitoring

Navigate to `GCP Console → Monitoring → Dashboards` to confirm the HRM Platform
dashboard was created. Alert policies are visible under `Monitoring → Alerting`.

The uptime check pings `https://YOUR_DOMAIN/api/health` every 60 seconds.
It will show failures until DNS and the SSL certificate are configured.

---

## 8. Destroy

Destroy is intentionally manual and requires explicit confirmation.

```
GitHub → Actions → Destroy Workflow → Run workflow → type "Destroy" → Run
```

**What the destroy pipeline does:**
1. Authenticates to GCP via WIF
2. Disables `deletion_protection` on Cloud SQL (required — Terraform cannot destroy
   a protected instance)
3. Runs `terragrunt run-all destroy` across all modules

**What is NOT destroyed automatically:**
- The GCS state bucket (created by bootstrap, not managed by env/dev Terragrunt)
- The WIF pool and CI/CD SA (created by bootstrap)
- Bootstrap local state file

To fully clean up:
```bash
# Remove state bucket
gsutil rm -r gs://dev-state-bucket-project-YOUR_PROJECT_ID

# Destroy bootstrap resources
cd global/bootstrap
terraform destroy
```

**Warning:** Destroying Cloud SQL removes all data. Ensure backups are taken first
if the database contains data you need.
