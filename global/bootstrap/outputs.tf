output "workload_identity_provider" {
    description = "Full WIF provider resource name — paste into GOOGLE_WIF_PROVIDER secret"
    value       = "projects/${var.project_id}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_pool.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github_provider.workload_identity_pool_provider_id}"
}

output "cicd_sa_email" {
    description = "CI/CD service account email — paste into GOOGLE_SA_EMAIL secret"
    value       = google_service_account.github_actions_sa.email
}

output "state_bucket_name" {
    description = "GCS state bucket name — paste into STATE_BUCKET variable"
    value       = google_storage_bucket.state_bucket.name
}