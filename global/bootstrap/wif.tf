data "google_client_config" "current" {}

resource "google_service_account" "github_actions_sa" {
    account_id      = "github-actions-tf-sa"
    display_name    = "Github Actions Terraform Service sa"
    project         = "${data.google_client_config.current.project}"
}

resource "google_project_iam_member" "github_actions_admin" {
    project         = "${data.google_client_config.current.project}"
    role            = "roles/editor"
    member          = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_iam_workload_identity_pool" "github_pool" {
    workload_identity_pool_id = "github-actions-pool"
    project         = "${data.google_client_config.current.project}"
    display_name    = "Github Actions pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
    workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
    workload_identity_pool_provider_id = "github-provider"
    project         = "${data.google_client_config.current.project}"

    attribute_mapping = {
        "google.subject" = "assertion.sub"
        "attribute.repository" = "assertion.repository"
    }

    oidc {
        issuer_uri = "https://token.actions.githubusercontent.com"
    }
}

resource "google_service_account_iam_member" "github_impersonation" {
    service_account_id = google_service_account.github_actions_sa.name
    role            = "roles/iam.workloadIdentityUser"
    member          = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/Y3GI/high_availability_hrm"
}