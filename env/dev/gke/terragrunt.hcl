include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/gke"
}

locals {
    root = read_terragrunt_config(find_in_parent_folders())
}

dependency "networking" {
    config_path = "../networking"

    mock_outputs_allowed_terraform_commands = ["plan"]
    mock_outputs = {
        network_id              = "mock-network-id"
        subnet_id               = "mock-subnet-id"
        pods_range_name         = "mock-pods-range-name"
        services_range_name     = "mock-services-range-name"
    }
}

inputs = {
    project_id              = local.root.locals.project_id
    region                  = local.root.locals.region
    env                     = local.root.locals.env
    email                   = local.root.locals.email
    tags                    = local.root.locals.tags
    network_id              = dependency.networking.outputs.network_id
    subnet_id               = dependency.networking.outputs.subnet_id
    pods_range_name         = dependency.networking.outputs.pods_range_name
    services_range_name     = dependency.networking.outputs.services_range_name
}