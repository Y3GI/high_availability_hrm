resource "google_service_account" "app_sa" {
    account_id      = "${var.env}-hrm-app-sa"
    display_name    = "HRM App Workload Service Account (${var.env})"
    project         = var.project_id
}

resource "google_service_account_iam_member" "workload_identity_binding" {
    service_account_id  = google_service_account.app_sa.id
    role                = "roles/iam.workloadIdentityUser"
    member              = "serviceAccount:${var.workload_identity_pool}[${var.k8s_namespace}/${var.k8s_sa_name}]"
}

resource "google_project_iam_member" "app_sa_cloudsql" {
    project             = var.project_id
    role                = "roles/cloudsql.client"
    member              = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "app_sa_secret_access" {
    project             = var.project_id
    secret_id           = var.db_password_secret_id
    role                = "roles/secretmanager.secretAccessor"
    member              = "serviceAccount:${google_service_account.app_sa.email}"
}

resource "google_project_iam_member" "app_sa_run_invoker" {
    project = var.project_id
    role    = "roles/run.invoker"
    member  = "serviceAccount:${google_service_account.app_sa.email}"
}