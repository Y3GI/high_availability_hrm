include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/storage"
}

locals {
    root = read_terragrunt_config(find_in_parent_folders())
}

dependency "networking" {
    config_path = "../networking"

    mock_outputs_allowed_terraform_commands = ["plan"]
    mock_outputs = {
        network_id          = "projects/mock-project/global/networks/mock-network"
    }
}

inputs = {
    project_id          = local.root.locals.project_id
    region              = local.root.locals.region
    env                 = local.root.locals.env
    email               = local.root.locals.email
    tags                = local.root.locals.tags
    network_id          = dependency.networking.outputs.network_id
}