resource "google_container_node_pool" "main_nodes" {
    name        = "${var.env}-nodes"
    project     = var.project_id
    location    = var.region
    cluster     = google_container_cluster.main_cluster.name

    node_count  = var.node_count

    management {
        auto_repair     = true
        auto_upgrade    = true
    }

    node_config {
        machine_type = var.machine_type
        disk_size_gb = var.disc_size_gb
        disk_type    = "pd-standard"

        tags = ["gke-node", var.env]

        service_account = google_service_account.gke_node_sa.email
        oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

        workload_metadata_config {
            mode = "GKE_METADATA"
        }

        shielded_instance_config {
            enable_secure_boot          = true
            enable_integrity_monitoring = true
        }
    }

    lifecycle {
        ignore_changes = [ node_count ]
    }
}