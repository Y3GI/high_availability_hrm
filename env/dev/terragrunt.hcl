locals {
    env             = "dev"
    project_id      = get_env("GOOGLE_CLOUD_PROJECT")
    region          = "europe-west4"
    email = "547283@student.fontys.nl"
    tags = {
        Environment = "Development"
        Owner       = "Boyan Stefanov"
        Project     = "High Availability HRM"
    }

    k8s_namespace   = "hrm"
    k8s_sa_name     = "hrm-app"

    domain          = "hrm.domain.com"
}

generate "provider" {
    path        = "provider.tf"
    if_exists   = "overwrite_terragrunt"
    contents    = <<EOF
provider "google"{
    project     = "${local.project_id}"
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
        bucket      = "${local.env}-state-bucket-project-${local.project_id}"
        prefix      = "${path_relative_to_include()}/terraform.tfstate"
        location    = "${local.region}"
    }
}

inputs = {
    project_id  = local.project_id
    env         = local.env
    region      = local.region
}