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