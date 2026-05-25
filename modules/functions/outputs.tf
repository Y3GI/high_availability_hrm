output "function_url" {
    value = google_cloudfunctions2_function.hrm_onboarding.service_config[0].uri
}

output "function_sa_email" {
    value = google_service_account.function_sa.email
}

output "github_token_secret_id" {
    value = google_secret_manager_secret.github_token.secret_id
}