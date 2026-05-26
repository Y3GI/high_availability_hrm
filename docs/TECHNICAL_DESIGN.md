# Technical Design Document
## High Availability HRM GitOps Platform

---

## 1. System Overview

The platform automates employee lifecycle management on Google Cloud Platform using
a GitOps-first approach. Git is the single source of truth for both infrastructure
state (Terraform/Terragrunt) and workload state (ArgoCD). No manual cluster operations
are required after initial deployment.

**Design principles:**
- Zero Trust — no implicit trust at any layer
- Immutable infrastructure — changes via code, never via console
- Blast radius minimisation — least privilege at every boundary
- Single source of truth — Git drives all state
- Full automation — bootstrap excepted, one pipeline run provisions everything

---

## 2. Network Architecture

### 2.1 VPC Design

```
Global VPC (hrm-gitops-vpc)
└── Regional Subnet: europe-west4 — 10.10.0.0/16
    ├── Secondary Range: k8s-pods-range    — 10.48.0.0/14  (~262k pod IPs)
    └── Secondary Range: k8s-service-range — 10.52.0.0/20  (~4k service IPs)
```

The VPC is global; subnets are regional. `auto_create_subnetworks = false` prevents
GCP from creating unmanaged subnets in every region. Secondary IP ranges are mandatory
for GKE VPC-native mode — pod IPs from `10.48.0.0/14`, service ClusterIPs from
`10.52.0.0/20`, referenced by name in `ip_allocation_policy`.

### 2.2 Egress

GKE nodes are private (no public IPs). Outbound traffic routes through:

```
GKE Node → Cloud Router (europe-west4) → Cloud NAT → Internet
```

NAT scoped to the private subnet (`LIST_OF_SUBNETWORKS`). `AUTO_ONLY` IP allocation —
GCP manages external IPs. Log config set to `ERRORS_ONLY`.

### 2.3 Firewall Rules

All rules centralised in `modules/networking/firewall.tf`.

| Rule | Direction | Source | Target Tag | Ports | Purpose |
|---|---|---|---|---|---|
| `allow-internal` | INGRESS | 10.10.0.0/16, 10.48.0.0/14, 10.52.0.0/20 | all | all | Node/pod/service mesh |
| `allow-health-checks` | INGRESS | 130.211.0.0/22, 35.191.0.0/16 | `gke-node` | TCP | GKE LB health probes |
| `allow-iap-ssh` | INGRESS | 35.235.240.0/20 | `gke-node` | TCP:22 | Break-glass SSH via IAP |

Default deny is implicit in GCP.

---

## 3. Zero Trust Security Model

### 3.1 Inbound (User → Application)

```
Internet
    → GCP Load Balancer (auto-created by GKE Ingress controller)
    → Identity-Aware Proxy (validates Google IAM identity)
    → Rejected if not roles/iap.httpsResourceAccessor
    → HRM app pod (hrm namespace)
```

IAP enforced at the load balancer backend via `BackendConfig` CRD. No VPN required.

**Workspace access** uses a second credential layer on top of IAP:

```
Authenticated user → https://cs3-hrm-app.duckdns.org/workspace
    → HRM app serves login form
    → POST /workspace/_auth: bcrypt verify employee ID + password against Cloud SQL
    → Session cookie issued (itsdangerous signed, 8h TTL, HttpOnly + Secure)
    → Subsequent requests: cookie verified, httpx proxies to internal pod
         http://{employee_id}-workspace.{department}.svc.cluster.local:8080/{path}
```

Employees use company-issued credentials (auto-generated employee ID + password).
Workspace pods have no public exposure — all traffic routes through the HRM proxy.

### 3.2 Internal (Pod → Database)

```
Pod (KSA: hrm-app, namespace: hrm)
    → Exchange KSA token for GCP SA token (Workload Identity / GKE_METADATA)
    → Cloud SQL Auth Proxy sidecar (mTLS tunnel via GCP SA identity)
    → Cloud SQL private IP (10.10.0.0/16:5432)
```

Pods never hold database passwords. Password stored in Secret Manager, read at
startup via the same Workload Identity mechanism.

### 3.3 CI/CD (GitHub Actions → GCP)

```
GitHub Actions OIDC JWT (short-lived, repo-scoped)
    → GCP STS (Security Token Service)
    → WIF Pool validates issuer + attribute condition (repo name)
    → Short-lived GCP access token (1 hour, CI/CD SA)
    → Terragrunt applies infrastructure
```

No JSON keys stored anywhere. Token expires after 1 hour.

### 3.4 Workload Identity Chain

Both sides of the binding must be present — mismatch silently fails:

```
Terraform (IAM side):
    roles/iam.workloadIdentityUser on GCP SA
    granted to: serviceAccount:PROJECT.svc.id.goog[namespace/ksa-name]

Kubernetes (manifest side):
    KSA annotated with:
    iam.gke.io/gcp-service-account: SA_EMAIL
```

---

## 4. Compute Architecture

### 4.1 GKE Cluster

| Property | Value | Rationale |
|---|---|---|
| Type | Standard | Explicit node pool control |
| Location | Regional (europe-west4) | Control plane across 3 zones |
| Node visibility | Private | No public IPs |
| Endpoint | Public, IAP-protected | kubectl without VPN |
| Workload Identity | Enabled | No credential files in pods |
| Dataplane | V2 (eBPF) | Replaces kube-proxy, enforces NetworkPolicy |
| Release channel | REGULAR | Managed upgrades |
| Shielded nodes | Enabled | Rootkit/bootkit protection |

### 4.2 Node Pool

| Property | Value |
|---|---|
| Machine type | e2-standard-2 (2 vCPU / 8 GB) |
| Nodes per zone | 1 (3 total across 3 zones) |
| Disk | 50 GB pd-standard |
| Auto-repair + auto-upgrade | Enabled |
| Service Account | Dedicated node SA (not default Compute SA) |
| Node SA roles | logWriter, metricWriter, monitoring.viewer, artifactregistry.reader |

### 4.3 Namespace Isolation

| Namespace | Purpose | Cloud SQL | Internet | Ingress from `hrm` |
|---|---|---|---|---|
| `argocd` | GitOps controller | No | Yes (GitHub) | No |
| `hrm` | Core application | Yes (proxy) | No | — |
| `software` | Employee workspaces | No | Yes (443) | Yes (port 8080) |
| `devops` | Employee workspaces | Yes (proxy) | Yes (443) | Yes (port 8080) |
| `db-engineering` | Employee workspaces | Yes (proxy + sidecar) | Yes (443) | Yes (port 8080) |

Department NetworkPolicies allow ingress from the `hrm` namespace on port 8080 so
the HRM reverse proxy can reach workspace pods. All other ingress is denied by default.

---

## 5. Application Architecture

### 5.1 HRM Application (Three-Tier)

```
Tier 1 — Frontend    Plain HTML/JS served by FastAPI (same container)
Tier 2 — Backend     FastAPI (Python) — REST API + Cloud Function calls
Tier 3 — Database    Cloud SQL PostgreSQL 15 via Cloud SQL Auth Proxy sidecar
```

**API endpoints:**

| Method | Path | Action |
|---|---|---|
| `GET` | `/` | Serve frontend |
| `GET` | `/api/employees` | List active employees |
| `POST` | `/api/employees` | Onboard: call Cloud Function → bcrypt hash → insert to DB |
| `DELETE` | `/api/employees/{id}` | Offboard: soft delete + call Cloud Function |
| `GET` | `/api/health` | Uptime check endpoint |
| `GET` | `/workspace`, `/workspace/` | Login form (no session) or proxy root (valid session) |
| `POST` | `/workspace/_auth` | Verify employee ID + password, issue session cookie |
| `POST` | `/workspace/_logout` | Clear session cookie |
| `*` | `/workspace/{path}` | Reverse proxy to employee's code-server pod |
| `WS` | `/workspace/{path}` | WebSocket proxy to employee's code-server pod |

Onboard calls the Cloud Function **first** to obtain the generated password, then
stores a bcrypt hash in Cloud SQL — plaintext never persists. If the Cloud Function
fails, no DB record is created. Offboard uses soft delete (`status = offboarded`)
— record retained for audit.

### 5.2 Cloud Function (Onboarding Engine)

HTTP trigger. Called by FastAPI backend. Reads GitHub PAT from Secret Manager
at runtime via Workload Identity SA.

**Onboard:**
1. Generate 24-char cryptographically random password (`secrets.choice`)
2. Render `workspace.yaml.tpl` via `str.replace()` substitution
3. Build base64-encoded k8s Secret manifest
4. Commit both files to `k8s/workspaces/DEPT/EMP_ID/` as single atomic git commit

**Offboard:**
1. Read current git tree
2. Build new tree excluding the employee's workspace path
3. Commit new tree — files removed from git
4. ArgoCD `prune: true` destroys the pod and secret

Single atomic commit ensures ArgoCD always sees a consistent state — never partial.

---

## 6. Data Architecture

### 6.1 Cloud SQL

| Property | Value |
|---|---|
| Engine | PostgreSQL 15 |
| Tier | db-g1-small |
| Availability | REGIONAL (hot standby, ~60s failover) |
| Public IP | Disabled |
| Deletion protection | Enabled |
| PITR | Enabled (WAL archiving) |
| Backups | Daily, 7-day retention |

### 6.2 PostgreSQL Role Bootstrap

Automated via `null_resource` with `local-exec` provisioner in `modules/storage`.
Runs `init.sql` via Cloud SQL Auth Proxy after instance creation. Idempotent —
uses `IF NOT EXISTS` and `ALTER DEFAULT PRIVILEGES` for future tables.

| Role | Permissions |
|---|---|
| `hrm_app` | SELECT, INSERT, UPDATE, DELETE on all tables |
| `devops_readonly` | SELECT only (debugging) |
| `db_engineer` | Full privileges |

### 6.3 State Management

```
GCS Bucket: dev-state-bucket-project-PROJECT_ID
├── env/dev/networking/terraform.tfstate
├── env/dev/gke/terraform.tfstate
├── env/dev/storage/terraform.tfstate
├── env/dev/security/terraform.tfstate
├── env/dev/functions/terraform.tfstate
└── env/dev/monitoring/terraform.tfstate
```

Each module has its own state file — a failed apply in one module does not affect
others. Native GCS locking (`use_lockfile = true`) — no DynamoDB equivalent needed.

---

## 7. GitOps Architecture

### 7.1 ArgoCD Application Model

```
AppProject: hrm-platform (scoped to this repo + specific namespaces)
├── Application: hrm-app               (k8s/apps/hrm — Helm chart)
├── Application: department-namespaces  (k8s/apps/departments — plain manifests)
└── ApplicationSet: department-workspaces
    └── Git generator: k8s/workspaces/*/*
        └── One Application auto-created per employee directory
```

`prune: true` + `selfHeal: true` on all Applications.

### 7.2 Workspace Lifecycle

```
Cloud Function commits k8s/workspaces/DEPT/EMP_ID/{workspace.yaml, secret.yaml}
    ↓ ArgoCD detects new directory (ApplicationSet Git generator)
    ↓ Application created → Pod + ClusterIP Service provisioned in namespace
    ↓ Employee visits /workspace → login form → session cookie → proxied to pod

Cloud Function deletes k8s/workspaces/DEPT/EMP_ID/
    ↓ ArgoCD detects deletion (prune: true)
    ↓ Pod + Service + Secret destroyed
    ↓ Session cookies for that employee_id rejected immediately (DB status = offboarded)
```

---

## 8. CI/CD Pipeline Architecture

### 8.1 Two Workflows

| Workflow | Trigger | Responsibility |
|---|---|---|
| `terraform_deploy.yml` | Push — `env/**`, `modules/**`, `hrm_app/**`, `k8s/**` or manual | Infrastructure + workspace images + HRM app image + cluster config |
| `terraform_destroy.yml` | Manual — type `Destroy` | Full teardown |

A single deploy workflow handles all changes — both infrastructure and application
code. `[skip ci]` in pipeline-generated commits (values.yaml, serviceaccount.yaml)
prevents loop triggering.

### 8.2 Deploy Pipeline Execution Order

```
WIF Authentication
    ↓ terragrunt run-all plan + apply
    ↓ [parallel] Pull codercom/code-server → retag → push to Artifact Registry (3 images)
    ↓ [parallel] Build hrm_app/ Docker image → push with git SHA tag
    ↓ Get GKE credentials
    ↓ Install ArgoCD (idempotent — skips if already running)
    ↓ Apply ArgoCD AppProject + Applications
    ↓ Read Terraform outputs (SA emails, Cloud SQL connection name, Cloud Function URL)
    ↓ envsubst: values.yaml.tpl → values.yaml
    ↓ envsubst: serviceaccount.yaml.tpl → serviceaccount.yaml (3 departments)
    ↓ kubectl apply iap-oauth-secret + hrm-db-secret + hrm-session-secret
    ↓ git commit generated files [skip ci]
```

### 8.3 Terragrunt Module DAG

```
networking
    ├── gke          (depends on: networking)
    │    └── security (depends on: gke + storage)
    └── storage      (depends on: networking)

functions   (no infrastructure dependencies)
monitoring  (no infrastructure dependencies)
```

Resolved automatically by Terragrunt `dependency` blocks. `run-all apply` never
needs manual `-target` flags.

---

## 9. Monitoring Architecture

| Resource | Configuration |
|---|---|
| Uptime check | HTTPS GET `/api/health` every 60s |
| Alert: app down | Uptime fails for 120s → email |
| Alert: SQL CPU | > 80% for 5 minutes → email |
| Alert: GKE memory | > 85% for 5 minutes → email |
| Dashboard | GKE CPU, GKE memory, Cloud SQL CPU, Cloud SQL connections |

Notification channel: email to `var.email` (from root Terragrunt locals).
