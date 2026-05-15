resource "google_compute_router" "main_router" {
    name            = "${var.env}-main-router"
    project         = var.project_id
    region          = var.region
    network         = google_compute_network.main_vpc.id
}

resource "google_compute_router_nat" "nat" {
    name            = "${var.env}-nat"
    project         = var.project_id
    router          = google_compute_router.main_router.name
    region          = var.region
    nat_ip_allocate_option = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"
    subnetwork {
        name = google_compute_subnetwork.k8s_subnet.id
        source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
    }
}