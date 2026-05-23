resource "google_service_account" "department_sa" {
    for_each        = toset(var.departments)
    account_id      = "${var.env}-${each.key}-sa"
    display_name    = "${each.key} Department Workload SA (${var.env})"
    project         = var.project_id
}

resource "google_service_account_iam_member" "department_wi_binding" {
    for_each            = toset(var.departments)
    service_account_id  = google_service_account.department_sa[each.key].name
    role                = "roles/iam.workloadIdentityUser"
    member              = "serviceAccount:${var.workload_identity_pool}[${each.key}/${each.key}-sa]"
}

resource "google_project_iam_member" "dept_cloudsql_access" {
    for_each    = toset(["devops", "db-engineering"])
    project     = var.project_id
    role        = "roles/cloudsql.client"
    member      = "serviceAccount:${google_service_account.department_sa[each.key].email}"
}