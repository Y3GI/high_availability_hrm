provider "aws" {
    region = "eu-central-1"
}

resource "aws_s3_bucket" "terraform_state" {
    bucket = "${var.env}-terraform-state-bucket-${data.aws_caller_identity.current.account_id}"
    #lifecycle {
    #    prevent_destroy = true
    #}
    tags = {
        Name        = "${var.env}-terraform-state-bucket"
        Environment = var.env
    }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_versioning" "terraform_state" {
    bucket = aws_s3_bucket.terraform_state.id

    versioning_configuration {
        status = "Enabled"
    }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state_encryption" {
    bucket = aws_s3_bucket.terraform_state.id

    rule{
        apply_server_side_encryption_by_default{
            sse_algorithm = "AES256"
        }
    }
}

resource "aws_s3_bucket_public_access_block" "state_public_access" {
    bucket = aws_s3_bucket.terraform_state.id

    block_public_acls = true
    block_public_policy = true
    ignore_public_acls = true
    restrict_public_buckets = true
}



resource "aws_s3_bucket_policy" "terraform_state" {
    bucket = aws_s3_bucket.terraform_state.id

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement" = [
            {
                "Sid": "ListBucket",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
                },
                "Action": "s3:ListBucket",
                "Resource": "arn:aws:s3:::${aws_s3_bucket.terraform_state.id}"
            },
            {
                "Sid": "StateOperations",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
                },
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject"
                ],
                "Resource": "arn:aws:s3:::${aws_s3_bucket.terraform_state.id}/*"
            },
            {
                "Sid": "LockOperations",
                "Effect": "Allow",
                "Principal": {
                    "AWS": "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
                },
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:DeleteObject"  
                ],
                "Resource": "arn:aws:s3:::${aws_s3_bucket.terraform_state.id}/*.tflock"
            }
        ]
    })
}