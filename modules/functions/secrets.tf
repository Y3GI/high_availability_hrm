resource "google_secret_manager_secret" "github_token" {
    secret_id   = "${var.env}-github-token"
    project     = var.project_id
    replication {
        auto{}
    }
}

resource "google_secret_manager_secret_version" "github_token_placeholder" {
    secret      = google_secret_manager_secret.github_token.id
    secret_data = "placeholder-replace-with-real-token"

    lifecycle {
        ignore_changes = [secret_data]
    }
}