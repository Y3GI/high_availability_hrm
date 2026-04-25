locals {
    gcp_apis = [
        "compute.googleapis.com",
        "container.googleapis.com",
        "sqladmin.googleapis.com",
        "iamcredentials.googleapis.com",
        "cloudresourcemanager.googleapis.com",
        "iap.googleapis.com"
    ]
}

resource "google_project_service" "enabled_apis" {
    for_each    = toset(local.gcp_apis)

    project     = "${data.google_client_config.current.project}"
    service     = each.key
    disable_on_destroy = false
}