include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/bootstrap-iam"
}

locals {
  root = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  aws_account_id = local.root.locals.aws_account_id

  github_owner      = "ggortsema"
  github_repository = "kharon"

  github_actions_role_name = "kharon-gha-terraform-plan-apply"

  tags = local.root.locals.common_tags
}
