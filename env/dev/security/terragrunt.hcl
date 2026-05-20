include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/security"
}

locals {
    root = read_terragrunt_config(find_in_parent_folders())
}

dependency "gke" {
    config_path = "../gke"

    mock_outputs_allowed_terraform_commands = ["plan"]
    mock_outputs = {
        workload_identity_pool = "mock-project.svc.id.goog"
    }
}

dependency "storage" {
    config_path = "../storage"

    mock_outputs_allowed_terraform_commands = ["plan"]
    mock_outputs = {
        db_instance_name        = "mock-db-instance-name"
        db_password_secret_id   = "mock-db-password-secret-id"
    }
}

inputs = {
    project_id              = local.root.locals.project_id
    region                  = local.root.locals.region
    env                     = local.root.locals.env
    email                   = local.root.locals.email
    tags                    = local.root.locals.tags
    workload_identity_pool  = dependency.gke.outputs.workload_identity_pool
    db_instance_name        = dependency.storage.outputs.db_instance_name
    db_password_secret_id   = dependency.storage.outputs.db_password_secret_id
    k8s_namespace           = local.root.locals.k8s_namespace
    k8s_sa_name             = local.root.locals.k8s_sa_name
    domain                  = local.root.locals.domain
}