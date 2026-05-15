resource "google_compute_firewall" "allow_internal" {
    name            = "${var.env}-firewall"
    project         = var.project_id
    network         = google_compute_network.main_vpc.name
    
    allow {
        protocol = "tcp"
    }
    allow {
        protocol = "udp"
    }
    allow {
        protocol = "icmp"
    }

    source_ranges = concat(
        ["10.10.0.0/16"],
        [for s in var.secondary_subnets : s.ip_cidr_range]
        )
}