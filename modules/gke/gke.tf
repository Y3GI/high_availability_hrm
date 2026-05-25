resource "google_container_cluster" "main_cluster"{
    name        = "${var.env}-gke-cluster"
    project     = var.project_id
    location    = var.region

    remove_default_node_pool    = true
    initial_node_count          = 1

    node_config {
        disk_type    = "pd-standard"
        disk_size_gb = 30
        machine_type = "e2-medium"
    }

    lifecycle {
        ignore_changes = [node_config]
    }

    network     = var.network_id
    subnetwork  = var.subnet_id

    ip_allocation_policy {
        cluster_secondary_range_name    = var.pods_range_name
        services_secondary_range_name   = var.services_range_name
    }

    private_cluster_config {
        enable_private_nodes    = true
        enable_private_endpoint = false
        master_ipv4_cidr_block  = "172.16.0.0/28"
    }

    workload_identity_config {
        workload_pool = "${var.project_id}.svc.id.goog"
    }

    master_authorized_networks_config {
        cidr_blocks {
            cidr_block   = "10.10.0.0/16"
            display_name = "node_subnet"
        }
        cidr_blocks {
            cidr_block   = "0.0.0.0/0"
            display_name = "github-actions"
        }
    }

    logging_config {
        enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    }

    monitoring_config {
        enable_components = ["SYSTEM_COMPONENTS", "APISERVER"]
        managed_prometheus {
            enabled = true
        }
    }

    datapath_provider = "ADVANCED_DATAPATH"

    release_channel {
        channel = "REGULAR"
    }

    master_auth {
        client_certificate_config {
            issue_client_certificate = false
        }
    }

    enable_shielded_nodes   = true
    deletion_protection     = false #<----Set to true in Prod
}