resource "google_compute_network" "main_vpc" {
    name                    = "${var.env}-vpc"
    project                 = var.project_id
    auto_create_subnetworks = false
    routing_mode            = "REGIONAL"
}