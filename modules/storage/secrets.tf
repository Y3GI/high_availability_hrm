resource "random_password" "db_password" {
    length  = 32
    special = true
}

resource "google_secret_manager_secret" "db_password" {
    secret_id   = "${var.env}-db-password" 
    project     = var.project_id

    replication {
        auto {}
    }
}

resource "google_secret_manager_secret_version" "db_password"{
    secret      = google_secret_manager_secret.db_password.id
    secret_data = random_password.db_password.result
}

resource "google_sql_user" "app_user" {
    name        = "${var.env}-hrm-app"
    project     = var.project_id
    instance    = google_sql_database_instance.main.name
    password    = random_password.db_password.result
}