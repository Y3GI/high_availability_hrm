resource "google_compute_subnetwork" "k8s_subnet" {
    name            = "${var.env}-subnet-${var.region}"
    project         = var.project_id
    region          = var.region
    network         = google_compute_network.main_vpc.id
    ip_cidr_range   = "10.10.0.0/16"
    private_ip_google_access = true

    dynamic "secondary_ip_range" {
        for_each = var.secondary_subnets
        content {
            range_name      = secondary_ip_range.value.range_name
            ip_cidr_range   = secondary_ip_range.value.ip_cidr_range
        }
    }
}