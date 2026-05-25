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

resource "google_service_account" "build_sa" {
    account_id      = "${var.env}-hrm-build-sa"
    display_name    = "HRM Cloud Functions Build SA (${var.env})"
    project         = var.project_id
}

resource "google_project_iam_member" "build_sa_roles" {
    for_each = toset([
        "roles/cloudbuild.builds.builder",
        "roles/artifactregistry.writer",
        "roles/storage.objectViewer",
        "roles/logging.logWriter",
    ])
    project = var.project_id
    role    = each.value
    member  = "serviceAccount:${google_service_account.build_sa.email}"
}

# IAM is eventually consistent — this pause lets storage.objectViewer propagate
# to the gcf-v2-sources-* staging bucket before Cloud Build starts the function build.
resource "time_sleep" "build_iam_propagation" {
    depends_on      = [google_project_iam_member.build_sa_roles]
    create_duration = "90s"
}