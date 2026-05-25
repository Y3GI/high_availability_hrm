# IAP OAuth brand + client must be created once in GCP Console (API shut down Mar 2026):
#   APIs & Services → OAuth consent screen → External → Configure
#   APIs & Services → Credentials → Create OAuth 2.0 Client ID (Web application)
# Store results as GitHub secrets: IAP_CLIENT_ID, IAP_CLIENT_SECRET

resource "google_iap_web_iam_member" "iap_access" {
    for_each    = toset(var.iap_members)
    project     = var.project_id
    role        = "roles/iap.httpsResourceAccessor"
    member      = each.value
}

resource "google_compute_global_address" "hrm_ingress_ip" {
    name    = "hrm-ingress-ip"
    project = var.project_id
}

resource "google_compute_managed_ssl_certificate" "hrm_cert" {
    name    = "hrm-cert"
    project = var.project_id

    managed {
        domains = [var.domain]
    }
}