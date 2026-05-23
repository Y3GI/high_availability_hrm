resource "google_artifact_registry_repository" "hrm_images" {
    repository_id   = "hrm"
    project         = var.project_id
    location        = var.region
    format          = "DOCKER"
    description     = "HRM workspace images"
}