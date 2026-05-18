resource "google_service_account" "gke_node_sa" {
    account_id   = "${var.env}-gke-node-sa"
    display_name = "GKE Node Pool Service Account (${var.env})"
    project      = var.project_id
}

resource "google_project_iam" "gke_node_sa_roles" {
    for_each = toset([
        "roles/logging.logWriter",
        "roles/monitoring.metricWriter",
        "roles/monitoring.viewer",
        "roles/artifactregistry.reader",
    ])

    project = var.project_id
    role    = each.value
    member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}