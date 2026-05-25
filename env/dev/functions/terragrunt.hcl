include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/functions"
}

inputs = {
    github_repo             = "Y3GI/high_availability_hrm"
    github_token_secret_id  = "dev-github-token"
}