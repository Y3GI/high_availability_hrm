output "ingress_ip" {
    description = "Global static IP for the HRM load balancer — point your DuckDNS domain here"
    value       = google_compute_global_address.hrm_ingress_ip.address
}

output "app_sa_email" {
    value       = google_service_account.app_sa.email
}

# Convenience output — the full annotation value for the KSA manifest
output "workload_identity_annotation" {
    value = "iam.gke.io/gcp-service-account=${google_service_account.app_sa.email}"
}
