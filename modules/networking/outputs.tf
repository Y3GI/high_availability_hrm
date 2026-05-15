output "network_id" {
    value = google_compute_network.main_vpc.id
}

output "network_name" {
    value = google_compute_network.main_vpc.name
}

output "subnet_id" {
    value = google_compute_subnetwork.k8s_subnet.id
}

output "pods_range_name" {
    value = google_compute_subnetwork.k8s_subnet.secondary_ip_range[0].range_name
}

output "services_range_name" {
    value = google_compute_subnetwork.k8s_subnet.secondary_ip_range[1].range_name
}