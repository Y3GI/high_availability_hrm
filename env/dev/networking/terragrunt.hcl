include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/networking"
}

locals {
    root = read_terragrunt_config(find_in_parent_folders())
}

inputs = {
    project_id  = local.root.locals.project_id
    region      = local.root.locals.region
    env         = local.root.locals.env
    email       = local.root.locals.email
    tags        = local.root.locals.tags
}