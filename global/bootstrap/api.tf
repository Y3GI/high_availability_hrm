locals {
    gcp_apis = [
        "compute.googleapis.com",
        "container.googleapis.com",
        "sqladmin.googleapis.com",
        "iamcredentials.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "iap.googleapis.com",
        "cloudfunctions.googleapis.com",
        "cloudbuild.googleapis.com",
        "monitoring.googleapis.com",
        "logging.googleapis.com",
        "secretmanager.googleapis.com",
        "servicenetworking.googleapis.com",
        "run.googleapis.com",
        "artifactregistry.googleapis.com"
    ]
}

resource "google_project_service" "enabled_apis" {
    for_each    = toset(local.gcp_apis)

    project     = var.project_id
    service     = each.key
    disable_on_destroy = false
}