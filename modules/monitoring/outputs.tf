output "dashboard_url" {
    description = "GCP Console URL for the monitoring dashboard"
    value       = "https://console.cloud.google.com/monitoring/dashboards/custom/${google_monitoring_dashboard.hrm_dashboard.id}?project=${var.project_id}"
}