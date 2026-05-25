data "google_client_config" "current" {}

locals {
    wif_roles = [
        "roles/editor",
        "roles/resourcemanager.projectIamAdmin",
        "roles/servicenetworking.networksAdmin",
        "roles/iam.serviceAccountAdmin",
        "roles/iam.serviceAccountUser",
        "roles/secretmanager.admin",
        "roles/iap.admin"
    ]
}

resource "google_service_account" "github_actions_sa" {
    account_id      = "github-actions-tf-sa"
    display_name    = "Github Actions Terraform Service sa"
    project         = "${var.project_id}"
}

resource "google_project_iam_member" "github_actions_roles" {
    for_each        = toset(local.wif_roles) 

    project         = "${var.project_id}"
    role            = each.key
    member          = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_iam_workload_identity_pool" "github_pool" {
    workload_identity_pool_id = "github-actions-pool"
    project         = "${var.project_id}"
    display_name    = "Github Actions pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
    workload_identity_pool_id = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
    workload_identity_pool_provider_id = "github-provider"
    project         = "${var.project_id}"

    attribute_mapping = {
        "google.subject" = "assertion.sub"
        "attribute.repository" = "assertion.repository"
    }

    attribute_condition = "attribute.repository == 'Y3GI/high_availability_hrm'"

    oidc {
        issuer_uri = "https://token.actions.githubusercontent.com"
    }
}

resource "google_service_account_iam_member" "github_impersonation" {
    service_account_id = google_service_account.github_actions_sa.name
    role            = "roles/iam.workloadIdentityUser"
    member          = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/Y3GI/high_availability_hrm"
}