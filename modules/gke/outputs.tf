output "cluster_id" {
    value = google_container_cluster.main_cluster.id
}

output "cluster_name" {
    value = google_container_cluster.main_cluster.name
}

output "cluster_endpoint" {
    value     = google_container_cluster.main_cluster.endpoint
    sensitive = true
}

output "workload_identity_pool" {
    value = "${var.project_id}.svc.id.goog"
}

output "node_sa_email" {
    value = google_service_account.gke_node_sa.email
}