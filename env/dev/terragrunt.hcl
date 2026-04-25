locals {
    env     = "dev"
    project = get_env("GOOGLE_CLOUD_PROJECT")
    region  = "europe-west4"
}

generate "provider" {
    path        = "provider.tf"
    if_exists   = "overwrite_terragrunt"
    contents    = <<EOF
provider "google"{
    project     = "${local.project}"
    region      = "${local.region}"
}
EOF
}

remote_state {
    backend     = "gcs"
    generate    = {
        path        = "backend.tf"
        if_exists   = "overwrite_terragrunt"
    }
    config = {
        bucket      = "${local.env}-state-bucket-project-${local.project}"
        prefix      = "${path_relative_to_include()}/terraform.tfstate"
        location    = "${local.region}"
    }
}

inputs = {
    project = local.project
    env     = local.env
    region  = local.region
}