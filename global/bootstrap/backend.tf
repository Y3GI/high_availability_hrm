resource "google_storage_bucket" "state_bucket" {
    name        = "${var.env}-state-bucket-project-${var.project_id}"
    location    = var.region
    project     = var.project_id

    #force_destroy = false #<-----uncomment when in prod

    versioning {
        enabled = true
    }

    uniform_bucket_level_access = true
    public_access_prevention    = "enforced"
}