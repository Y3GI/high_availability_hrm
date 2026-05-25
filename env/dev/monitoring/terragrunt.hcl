include "root" {
    path = find_in_parent_folders()
}

terraform {
    source = "../../../modules/monitoring"
}

# No dependency blocks needed — monitoring only needs project/region/email/domain/tags
# which all come from the root inputs block via include "root" (Terragrunt merges them)