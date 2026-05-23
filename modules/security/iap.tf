resource "google_iap_brand" "default" {
    support_email       = var.email
    application_title   = "HRM Onboarding Platform"
    project             = var.project_id
}

resource "google_iap_client" "default" {
    display_name    = "HRM IAP Client"
    brand           = google_iap_brand.default.name
}

resource "google_iap_web_iam_member" "iap_access" {
    project         = var.project_id
    role            = "roles/iap.httpsResourceAccessor"
    member          = "domain:yourdomain.com"
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