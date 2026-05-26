# Services Overview
## High Availability HRM GitOps Platform

Complete reference of every GCP service, Kubernetes resource, and tool used in
this platform — what it is, why it was chosen, and how it is configured.

---

## GCP Services

### Compute

#### GKE Standard

Container orchestration layer. Chosen over Autopilot to demonstrate explicit node
pool provisioning. Regional deployment replicates the control plane across three
availability zones for HA.

**Cluster config:**
- `remove_default_node_pool = true` — replaced by explicitly configured managed pool
- `enable_private_nodes = true` — nodes have no public IPs
- `enable_private_endpoint = false` — API server reachable publicly (IAP-protected)
- `master_ipv4_cidr_block = 172.16.0.0/28` — VPC peering range for control plane
- `datapath_provider = ADVANCED_DATAPATH` — Dataplane V2 (eBPF), replaces kube-proxy
- `workload_identity_config` — pod-level GCP identity without credential files
- `release_channel = REGULAR` — managed upgrades, ~2 week validation window
- `enable_shielded_nodes = true` — Secure Boot + integrity monitoring

**Node pool:**
- `e2-standard-2` — 2 vCPU / 8 GB, cost-optimised for $300 trial
- `node_count = 1` per zone → 3 nodes total
- `auto_repair + auto_upgrade = true`
- `workload_metadata_config { mode = GKE_METADATA }` — required for Workload Identity
- `lifecycle { ignore_changes = [node_count] }` — autoscaler owns count at runtime
- Dedicated node SA — not the default Compute SA

#### Cloud Functions Gen 2

Serverless HTTP trigger for the onboarding/offboarding engine. Gen 2 runs on
Cloud Run internally — better cold start, longer timeout than Gen 1.

- Runtime: Python 3.11
- Min instances: 0 (scales to zero — cost saving on $300 trial)
- GitHub PAT injected as secret environment variable from Secret Manager
- Dedicated function SA with `secretmanager.secretAccessor` + `run.invoker`

---

### Networking

#### VPC

Global network boundary. Unlike AWS, a GCP VPC spans all regions — subnets are
regional attachments to the global network.

- `auto_create_subnetworks = false` — no unmanaged subnets in other regions
- `routing_mode = REGIONAL` — routers only learn routes within their region

#### Cloud Router + Cloud NAT

Managed egress for private GKE nodes. Cloud NAT is distributed — no single VM,
no bottleneck, no failure point.

- `nat_ip_allocate_option = AUTO_ONLY` — GCP manages external IPs
- `source_subnetwork_ip_ranges_to_nat = LIST_OF_SUBNETWORKS` — scoped to private subnet
- `log_config { filter = ERRORS_ONLY }` — captures failures, avoids log volume

#### Cloud Load Balancing

L7 load balancer automatically provisioned by GKE when the `Ingress` manifest is
applied. Not a Terraform resource — GKE's ingress controller manages its lifecycle.
Attached to the Terraform-reserved static IP for stability across redeployments.

#### VPC Firewall

Centralised traffic rules targeting instances via network tags. Three rules:
1. `allow-internal` — all traffic between nodes, pods, services
2. `allow-health-checks` — GCP health check probers (`130.211.0.0/22`, `35.191.0.0/16`)
3. `allow-iap-ssh` — IAP tunnel source (`35.235.240.0/20`) for break-glass SSH

---

### Security

#### Identity-Aware Proxy (IAP)

Zero Trust access at the load balancer layer. Enforces Google IAM before any request
reaches the VPC. Replaces VPN entirely.

- OAuth client: `google_iap_brand` + `google_iap_client`
- Attached to GKE LB backend via `BackendConfig` Kubernetes resource
- Access: `roles/iap.httpsResourceAccessor` IAM binding
- `iap-oauth-secret` k8s Secret stores client credentials for `BackendConfig`

#### Workload Identity

Kubernetes pods authenticate as GCP Service Accounts without credential files.
Two-sided binding — both must be present:

1. **IAM (Terraform):** `roles/iam.workloadIdentityUser` on GCP SA granted to
   `serviceAccount:PROJECT.svc.id.goog[namespace/ksa-name]`
2. **k8s (manifest):** KSA annotated with `iam.gke.io/gcp-service-account: SA_EMAIL`

Pod exchanges its KSA token for a GCP access token via the node metadata server
(`GKE_METADATA` mode). Mismatch between the two sides silently fails — pod gets 403.

#### Workload Identity Federation (WIF)

GitHub Actions authenticates as a GCP Service Account without JSON keys.
Bootstrapped in `global/bootstrap/`. Trust scoped to specific repo via
`attribute_condition` — forks cannot authenticate.

#### Secret Manager

Encrypted secret storage:
- `dev-db-password` — PostgreSQL password (app reads at startup)
- `dev-github-token` — GitHub PAT (Cloud Function reads at runtime)
- `dev-iap-client-secret` — IAP OAuth secret (output to pipeline, stored as k8s Secret)

All secrets: `replication { auto {} }` — GCP manages cross-region replication.

#### Service Accounts

One SA per component — never the default Compute SA:

| SA | Used by | Key roles |
|---|---|---|
| `dev-cicd-sa` | GitHub Actions | Terraform apply permissions |
| `dev-gke-node-sa` | GKE nodes | logWriter, metricWriter, artifactregistry.reader |
| `dev-hrm-app-sa` | HRM app pods | cloudsql.client, secretmanager.secretAccessor, run.invoker |
| `dev-hrm-function-sa` | Cloud Function | secretmanager.secretAccessor |
| `dev-software-sa` | Software dept pods | Workload Identity base only |
| `dev-devops-sa` | DevOps dept pods | cloudsql.client |
| `dev-db-engineering-sa` | DB Eng pods | cloudsql.client |

`roles/run.invoker` on the HRM app SA allows the FastAPI backend to call the
Cloud Function (Cloud Run) with a valid identity token obtained from the GKE
metadata server.

`google_project_iam_member` (additive) used throughout — never `google_project_iam_binding`
(authoritative). `iam_binding` removes unlisted members on apply — unsafe in modules.

---

### Storage

#### Cloud SQL for PostgreSQL

Regional HA relational database. Chosen over AlloyDB for budget compatibility
while maintaining production-credible HA.

- `availability_type = REGIONAL` — hot standby, ~60s automatic failover
- `ipv4_enabled = false` — private access only, no public IP attack surface
- `deletion_protection = true` — must set `false` before `terraform destroy`
- `point_in_time_recovery_enabled = true` — WAL archiving, restore to any second
- Private service access via `google_service_networking_api` VPC peering
- Access exclusively via Cloud SQL Auth Proxy (mTLS)

**PostgreSQL role bootstrap:** automated via `null_resource` `local-exec` provisioner.
Runs idempotent `init.sql` (IF NOT EXISTS + ALTER DEFAULT PRIVILEGES) via Auth Proxy
after instance creation. Re-runs only if `init.sql` file hash changes.

#### Google Cloud Storage

Two purposes:
1. **Terraform state** — one bucket, per-module prefix paths, native locking
2. **Cloud Function source** — zipped function code uploaded before deployment

Versioning enabled on state bucket — previous state versions retained.

#### Artifact Registry

Docker image registry in `europe-west4` — same region as GKE for fast pulls,
no cross-region egress costs. Repository: `europe-west4-docker.pkg.dev/PROJECT/hrm`.

Images pushed by the deploy pipeline:
- `software-workspace:latest` — `codercom/code-server` retagged
- `devops-workspace:latest` — `codercom/code-server` retagged
- `db-engineering-workspace:latest` — `codercom/code-server` retagged
- `hrm-app:{git-sha}` — built from `hrm_app/Dockerfile`, tagged with commit SHA

GKE nodes pull from Artifact Registry automatically via node SA `artifactregistry.reader`.
No Docker Hub credentials needed on nodes.

---

### Monitoring

#### Cloud Monitoring

Three alert policies with email notification to owner address:
- **HRM app down** — uptime check fails for 120s
- **Cloud SQL CPU > 80%** — sustained 5 minutes
- **GKE node memory > 85%** — sustained 5 minutes

One uptime check — HTTPS GET `/api/health` every 60s from multiple GCP regions.
One dashboard — 4 panels: GKE CPU, GKE memory, Cloud SQL CPU, Cloud SQL connections.

---

## Kubernetes Resources

### ArgoCD

GitOps controller in `argocd` namespace. Continuously reconciles cluster state
with git. `prune: true` deletes resources removed from git. `selfHeal: true`
reverts manual kubectl changes within seconds.

**AppProject** scopes trust to this repository and specific namespaces. Prevents
ArgoCD from deploying to unintended namespaces or reading from other repos.

**Application** manages static workloads (HRM app, department namespaces).

**ApplicationSet** with Git directory generator dynamically creates one Application
per employee workspace folder. Adding a folder to git creates a pod. Removing it
destroys the pod. One ApplicationSet manages unlimited workspaces automatically.

### Helm (HRM Application)

HRM core app packaged as Helm chart. `values.yaml` is pipeline-generated from
`values.yaml.tpl` via `envsubst` — project-specific values injected without hardcoding.

### NetworkPolicy

Pod-level firewall. `policyTypes: [Ingress, Egress]` with no catch-all = default
deny both directions. Always includes DNS egress (UDP 53) — without it pods cannot
resolve any hostname including internal Kubernetes services.

### ResourceQuota

Per-namespace limits: `pods: 20`, `requests.cpu: 4`, `requests.memory: 8Gi`,
`limits.cpu: 8`, `limits.memory: 16Gi`. Prevents one department consuming all
cluster capacity.

### BackendConfig

GKE CRD attaching IAP to the HRM service load balancer backend. Referenced by
the Service via annotation `cloud.google.com/backend-config`.

---

## Infrastructure as Code

### Terraform

Declares all GCP resources. Modules are reusable — no environment-specific values
inside module code. All configuration injected via variables from Terragrunt.

### Terragrunt

Wraps Terraform for two purposes:
1. **DRY config** — root `terragrunt.hcl` defines shared locals once (`project_id`,
   `region`, `env`, `email`, `tags`, `k8s_namespace`, `k8s_sa_name`, `domain`).
   Child configs inherit via `include "root"`.
2. **DAG resolution** — `dependency` blocks declare inter-module relationships.
   `run-all apply` resolves the graph automatically. No `-target` flags needed.

`mock_outputs` on dependency blocks allow `run-all plan` before infrastructure
exists — enables CI validation on pull requests.

---

## Application Stack

### FastAPI (HRM Backend)

Python async web framework. Serves both the REST API and the static HTML frontend
from the same container. Also acts as a reverse proxy for all workspace traffic
(`/workspace/*`). Connects to Cloud SQL via `asyncpg` connection pool.
Reads DB password from Secret Manager at startup via Workload Identity.

### code-server

Browser-based VS Code IDE running in each employee workspace pod on port 8080.
The password is stored in a Kubernetes Secret (mounted as `$PASSWORD` env var).
Employees do not access code-server directly — all traffic is reverse-proxied by
the HRM app (see Workspace Reverse Proxy below).

### Workspace Session Authentication

Employees access `https://cs3-hrm-app.duckdns.org/workspace` and are presented
with a login form (employee ID + password). The HRM backend verifies the password
against a bcrypt hash stored in Cloud SQL, then issues a signed `HttpOnly` session
cookie (`workspace_session`) using `itsdangerous.URLSafeTimedSerializer`. Sessions
expire after 8 hours. Stale cookies (e.g. after offboarding) are detected and
cleared automatically — the login form is shown again.

This model means employees use company-issued credentials (not personal Google
accounts) to access their workspaces. IAP protects the overall platform; workspace
access within IAP uses a separate credential layer.

### Workspace Reverse Proxy

The HRM app pod proxies all `/workspace/{path}` traffic to the authenticated
employee's code-server pod using its internal Kubernetes DNS name:

```
https://cs3-hrm-app.duckdns.org/workspace/{path}
    → HRM app verifies session cookie
    → httpx forwards to http://{employee_id}-workspace.{department}.svc.cluster.local:8080/{path}
```

WebSocket connections (required by code-server for terminal and file sync) are
proxied over the same route using the `websockets` library. No NodePort or
LoadBalancer is needed on workspace pods — all routing is internal.

### Cloud SQL Auth Proxy

Sidecar container establishing an mTLS tunnel to Cloud SQL using Workload Identity.
App connects to `127.0.0.1:5432` — no awareness of Cloud SQL, IAM, or TLS in
application code. Required in HRM app pod and db-engineering workspace pods.

### PyGithub

Python library used by the Cloud Function to commit workspace manifests via the
GitHub API. Commits workspace.yaml + secret.yaml as a single atomic git commit —
ArgoCD always sees a consistent state, never a partial onboarding.
