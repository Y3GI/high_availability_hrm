resource "google_storage_bucket" "function_source" {
    name                        = "${var.env}-function-source-${var.project_id}"
    project                     = var.project_id
    location                    = var.region
    uniform_bucket_level_access = true
    force_destroy               = true
}

data "archive_file" "function_zip" {
    type        = "zip"
    source_dir  = "${path.module}/source"
    output_path = "/tmp/hrm-function.zip"
}

resource "google_storage_bucket_object" "function_zip" {
    name        = "hrm-function-${data.archive_file.function_zip.output_md5}.zip"
    bucket      = google_storage_bucket.function_source.name
    source      = data.archive_file.function_zip.output_path
}

resource "google_cloudfunctions2_function" "hrm_onboarding" {
    name        = "${var.env}-hrm-onboarding-function"
    project     = var.project_id
    location    = var.region

    depends_on = [
        time_sleep.build_iam_propagation,
        google_secret_manager_secret_version.github_token_placeholder,
    ]

    build_config {
        runtime         = "python311"
        entry_point     = "handle_hr_event"
        service_account = google_service_account.build_sa.id
        source {
            storage_source {
                bucket = google_storage_bucket.function_source.name
                object = google_storage_bucket_object.function_zip.name
            }
        }
    }
    
    service_config {
        min_instance_count      = 0
        max_instance_count      = 3
        available_memory        = "256M"
        timeout_seconds         = 60
        service_account_email   = google_service_account.function_sa.email
        environment_variables = {
            GITHUB_REPO             = var.github_repo
            GOOGLE_CLOUD_PROJECT    = var.project_id
            ENV                     = var.env
        }
        secret_environment_variables {
            key         = "GITHUB_TOKEN"
            project_id  = var.project_id
            secret      = google_secret_manager_secret.github_token.secret_id
            version     = "latest"
        }
    }
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
    project         = var.project_id
    location        = var.region
    cloud_function  = google_cloudfunctions2_function.hrm_onboarding.name
    role            = "roles/cloudfunctions.invoker"
    member          = "serviceAccount:${google_service_account.function_sa.email}"
}
