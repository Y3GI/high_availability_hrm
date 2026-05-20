# Consumed by modules/security to grant the app SA access to Cloud SQL
output "instance_connection_name" {
    value = google_sql_database_instance.main.connection_name
}

output "db_instance_name" {
    value = google_sql_database_instance.main.name
}

output "db_name" {
    value = google_sql_database.app_db.name
}

output "db_user" {
    value = google_sql_user.app_user.name
}

# The app reads the password from Secret Manager at runtime — not from Terraform output
output "db_password_secret_id" {
    value = google_secret_manager_secret.db_password.secret_id
}

output "private_ip" {
    value     = google_sql_database_instance.main.private_ip_address
    sensitive = true
}