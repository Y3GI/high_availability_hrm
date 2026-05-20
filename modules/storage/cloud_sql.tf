resource "google_compute_global_address" "private_ip_range" {
    name            = "${var.env}-sql-private-range"
    project         = var.project_id
    purpose         = "VPC_PEERING"
    address_type    = "INTERNAL"
    prefix_length   = 16
    network         = var.network_id
}

resource "google_service_networking_api" "private_vpc_connection" {
    provider                = google

    service                 = "servicenetworking.googleapis.com"
    network                 = var.network_id
    reserved_peering_ranges = [ google_compute_global_address.private_ip_range.name ]
}

resource "google_sql_database_instance" "main" {
    name                = "${var.env}-sql-database"
    project             = var.project_id
    region              = var.region
    database_version    = "POSTGRES_15"

    #deletion_protection = true <----Uncomment in Prod

    settings {
        tier                = var.db_tier
        availability_type   = "REGIONAL"

        backup_configuration {
            enabled                         = true
            start_time                      = "03:00"
            point_in_time_recovery_enabled  = true
            transaction_log_retention_days  = 7
            backup_retention_settings {
                retained_backups = 7
            }
        }

        ip_configuration {
            ipv4_enabled                                    = false
            private_network                                 = var.network_id
            enable_private_path_for_google_cloud_services   = true
        }

        maintenance_window {
            day             = 7
            hour            = 4
            update_track    = "stable"
        }

        database_flags {
            name    = "log_checkpoints"
            value   = "on"
        }

        database_flags {
            name    = "log_connections"
            value   = "on"
        }

        database_flags {
            name    = "log_disconnections"
            value   = "on"
        }
    }

    depends_on = [ google_service_networking_api.private_vpc_connection ]
}

resource "google_sql_database" "app_db" {
    name        = "${var.env}-hrm-db"
    project     = var.project_id
    instance    = google_sql_database_instance.main.name
}