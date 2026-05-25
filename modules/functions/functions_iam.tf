resource "google_service_account" "function_sa" {
    account_id      = "${var.env}-hrm-function-sa"
    display_name    = "HRM Cloud Function SA (${var.env})"
    project         = var.project_id
}

resource "google_project_iam_member" "function_sa_roles" {
    for_each = toset([
        "roles/secretmanager.secretAccessor",
        "roles/cloudfunctions.invoker",
        "roles/run.invoker",
    ])
    project = var.project_id
    role    = each.value
    member  = "serviceAccount:${google_service_account.function_sa.email}"
}

data "google_project" "project" {
    project_id = var.project_id
}

resource "google_project_iam_member" "cloudbuild_sa_roles" {
    for_each = toset([
        "roles/artifactregistry.writer",
        "roles/storage.objectViewer",
        "roles/logging.logWriter",
    ])
    project = var.project_id
    role    = each.value
    member  = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}