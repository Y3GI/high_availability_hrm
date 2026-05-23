resource "google_secret_manager_secret" "github_token" {
    secret_id   = "${var.env}-github-token"
    project     = var.project_id
    replication {
        auto{}
    }
}