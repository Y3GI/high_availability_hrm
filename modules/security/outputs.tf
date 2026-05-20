output "iap_client_id" {
    value       = google_iap_client.default.client_id
    sensitive   = true
}

output "iap_client_secret" {
    value       = google_iap_client.default.secret
    sensitive   = true
}

output "ingress_ip" {
    value       = google_compute_global_address.hrm_ingress_ip
    sensitive   = true
}

output "app_sa_email" {
    value       = google_service_account.app_sa.email
}

# Convenience output — the full annotation value for the KSA manifest
output "workload_identity_annotation" {
    value = "iam.gke.io/gcp-service-account=${google_service_account.app_sa.email}"
}
