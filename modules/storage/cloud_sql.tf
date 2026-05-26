terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

resource "google_compute_global_address" "private_ip_range" {
    name            = "${var.env}-sql-private-range"
    project         = var.project_id
    purpose         = "VPC_PEERING"
    address_type    = "INTERNAL"
    prefix_length   = 16
    network         = var.network_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
    service                 = "servicenetworking.googleapis.com"
    network                 = var.network_id
    reserved_peering_ranges = [ google_compute_global_address.private_ip_range.name ]

    # Ensures Cloud SQL is destroyed before this connection on `terraform destroy`,
    # preventing the "Producer services still using this connection" GCP timing error.
    depends_on = [ google_sql_database_instance.main ]
}

resource "google_sql_database_instance" "main" {
    name                = "${var.env}-sql-database"
    project             = var.project_id
    region              = var.region
    database_version    = "POSTGRES_15"

    deletion_protection = false #<----Set to true in Prod

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

    depends_on = [ google_service_networking_connection.private_vpc_connection ]
}

resource "google_sql_database" "app_db" {
    name        = "${var.env}-hrm-db"
    project     = var.project_id
    instance    = google_sql_database_instance.main.name
}

resource "null_resource" "db_init" {
    depends_on = [ 
        google_sql_database.app_db,
        google_sql_database_instance.main,
        google_sql_user.app_user
    ]

    triggers = {
        sql_hash = filemd5("${path.module}/init.sql")
    }

    provisioner "local-exec" {
    command = <<-EOT
      # Download Cloud SQL Auth Proxy
      curl -o cloud-sql-proxy \
        https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.8.0/cloud-sql-proxy.linux.amd64
      chmod +x cloud-sql-proxy

      # Start proxy in background
      ./cloud-sql-proxy \
        ${google_sql_database_instance.main.connection_name} \
        --port=5433 &
      PROXY_PID=$!

      # Wait for proxy to be ready
      sleep 5

      # Run the init script
      PGPASSWORD=${random_password.db_password.result} psql \
        -h 127.0.0.1 \
        -p 5433 \
        -U ${google_sql_user.app_user.name} \
        -d ${google_sql_database.app_db.name} \
        -f ${path.module}/init.sql

      # Clean up
      kill $PROXY_PID
    EOT
  }
}

