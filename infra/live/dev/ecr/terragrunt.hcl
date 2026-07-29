include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/ecr"
}

locals {
  root = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  name = "${local.root.locals.project}-${local.root.locals.environment}"

  tags = merge(
    local.root.locals.common_tags,
    {
      Name = "${local.root.locals.project}-${local.root.locals.environment}"
    }
  )
}
