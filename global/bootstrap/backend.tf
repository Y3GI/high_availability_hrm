resource "google_storage_bucket" "state_bucket" {
    name        = "${var.env}-state-bucket-project-${data.google_client_config.current.project}"
    location    = var.region
    project     = "${data.google_client_config.current.project}"

    #force_destroy = false #<-----uncomment when in prod

    versioning {
        enabled = true
    }

    public_access_prevention = "enforced"
}