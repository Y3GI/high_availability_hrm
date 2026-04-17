# S3 Backend Outputs
output "terraform_state_bucket_name" {
    description = "The name of the Terraform state S3 bucket"
    value       = aws_s3_bucket.terraform_state.id
}

output "terraform_state_bucket_arn" {
    description = "The ARN of the Terraform state S3 bucket"
    value       = aws_s3_bucket.terraform_state.arn
}

output "terraform_state_bucket_region" {
    description = "The region of the Terraform state S3 bucket"
    value       = aws_s3_bucket.terraform_state.region
}

output "terraform_state_bucket_versioning_enabled" {
    description = "Whether versioning is enabled on the Terraform state bucket"
    value       = aws_s3_bucket_versioning.terraform_state.versioning_configuration[0].status
}

# GitHub Actions OIDC Outputs
output "github_oidc_provider_arn" {
    description = "The ARN of the GitHub Actions OIDC provider"
    value       = aws_iam_openid_connect_provider.github.arn
}

output "github_oidc_provider_url" {
    description = "The URL of the GitHub Actions OIDC provider"
    value       = aws_iam_openid_connect_provider.github.url
}

output "github_oidc_provider_thumbprint" {
    description = "The thumbprint of the GitHub Actions OIDC provider"
    value       = aws_iam_openid_connect_provider.github.thumbprint_list
}

output "github_actions_role_arn" {
    description = "The ARN of the GitHub Actions IAM role"
    value       = aws_iam_role.github_actions.arn
}

output "github_actions_role_name" {
    description = "The name of the GitHub Actions IAM role"
    value       = aws_iam_role.github_actions.name
}

output "github_actions_role_id" {
    description = "The ID of the GitHub Actions IAM role"
    value       = aws_iam_role.github_actions.id
}

output "github_actions_policy_attachment_name" {
    description = "The role that has the AdministratorAccess policy attached"
    value       = aws_iam_role_policy_attachment.github_actions_admin.role
}

output "aws_account_id" {
    description = "The AWS account ID"
    value       = data.aws_caller_identity.current.account_id
}