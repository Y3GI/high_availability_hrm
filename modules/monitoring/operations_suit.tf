# Uptime check — pings the HRM app every 60s from multiple GCP regions
resource "google_monitoring_uptime_check_config" "hrm_uptime" {
    display_name = "${var.env}-hrm-uptime-check"
    project      = var.project_id
    timeout      = "10s"
    period       = "60s"

    http_check {
        path         = "/api/health"
        port         = 443
        use_ssl      = true
        validate_ssl = true
    }

    monitored_resource {
        type = "uptime_url"
        labels = {
            project_id = var.project_id
            host       = var.domain
        }
    }
}

# Alert if uptime check fails from 2+ regions
resource "google_monitoring_alert_policy" "hrm_down" {
    display_name = "${var.env}-hrm-down"
    project      = var.project_id
    combiner     = "OR"

    conditions {
        display_name = "HRM app unreachable"
        condition_threshold {
            filter          = "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" resource.type=\"uptime_url\""
            comparison      = "COMPARISON_LT"
            threshold_value = 1
            duration        = "120s"
            aggregations {
                alignment_period   = "60s"
                per_series_aligner = "ALIGN_NEXT_OLDER"
                cross_series_reducer = "REDUCE_COUNT_TRUE"
                group_by_fields    = ["resource.label.host"]
            }
        }
    }

    notification_channels = [google_monitoring_notification_channel.email.name]

    alert_strategy {
        auto_close = "1800s"
    }
}

# Alert if Cloud SQL CPU > 80% for 5 minutes
resource "google_monitoring_alert_policy" "cloudsql_cpu" {
    display_name = "${var.env}-cloudsql-high-cpu"
    project      = var.project_id
    combiner     = "OR"

    conditions {
        display_name = "Cloud SQL CPU above 80%"
        condition_threshold {
            filter          = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
            comparison      = "COMPARISON_GT"
            threshold_value = 0.8
            duration        = "300s"
            aggregations {
                alignment_period   = "60s"
                per_series_aligner = "ALIGN_MEAN"
            }
        }
    }

    notification_channels = [google_monitoring_notification_channel.email.name]
}

# Alert if GKE node memory > 85%
resource "google_monitoring_alert_policy" "gke_memory" {
    display_name = "${var.env}-gke-high-memory"
    project      = var.project_id
    combiner     = "OR"

    conditions {
        display_name = "GKE node memory above 85%"
        condition_threshold {
            filter          = "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\" resource.type=\"k8s_node\""
            comparison      = "COMPARISON_GT"
            threshold_value = 0.85
            duration        = "300s"
            aggregations {
                alignment_period   = "60s"
                per_series_aligner = "ALIGN_MEAN"
            }
        }
    }

    notification_channels = [google_monitoring_notification_channel.email.name]
}

# Email notification channel
resource "google_monitoring_notification_channel" "email" {
    display_name = "${var.env}-email-alerts"
    project      = var.project_id
    type         = "email"

    labels = {
        email_address = var.email
    }
}

# Dashboard — GKE + Cloud SQL overview
resource "google_monitoring_dashboard" "hrm_dashboard" {
  project        = var.project_id
  dashboard_json = jsonencode({
    displayName = "${var.env} HRM Platform Dashboard"
    gridLayout = {
      columns = 2
      widgets = [
        {
          title = "GKE Node CPU Utilisation"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/node/cpu/allocatable_utilization\" resource.type=\"k8s_node\""
                  aggregation = {
                    alignmentPeriod = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "GKE Node Memory Utilisation"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"kubernetes.io/node/memory/allocatable_utilization\" resource.type=\"k8s_node\""
                  aggregation = {
                    alignmentPeriod = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Cloud SQL CPU Utilisation"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"cloudsql.googleapis.com/database/cpu/utilization\" resource.type=\"cloudsql_database\""
                  aggregation = {
                    alignmentPeriod = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        },
        {
          title = "Cloud SQL Connections"
          xyChart = {
            dataSets = [{
              timeSeriesQuery = {
                timeSeriesFilter = {
                  filter = "metric.type=\"cloudsql.googleapis.com/database/network/connections\" resource.type=\"cloudsql_database\""
                  aggregation = {
                    alignmentPeriod = "60s"
                    perSeriesAligner = "ALIGN_MEAN"
                  }
                }
              }
            }]
          }
        }
      ]
    }
  })
}