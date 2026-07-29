locals {
  project         = "kharon"
  environment     = "dev"
  aws_region      = "us-east-1"
  aws_account_id  = "359546647832"
  state_bucket    = "${local.project}-${local.aws_account_id}-${local.environment}-tfstate"
  state_lock_table = "${local.project}-${local.aws_account_id}-${local.environment}-tfstate-lock"

  common_tags = {
    Project     = local.project
    Environment = local.environment
    ManagedBy   = "terragrunt"
  }
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local.state_bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = local.aws_region
    encrypt        = true
    dynamodb_table = local.state_lock_table
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_region}"
}
EOF
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  backend "s3" {}
}
EOF
}

inputs = {
  aws_region  = local.aws_region
  project     = local.project
  environment = local.environment
  common_tags = local.common_tags
}