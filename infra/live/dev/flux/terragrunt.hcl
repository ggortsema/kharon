include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/flux-bootstrap"
}

dependency "eks" {
  config_path = "../eks"
}

locals {
  root = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  cluster_name      = dependency.eks.outputs.cluster_name
  aws_region        = local.root.locals.aws_region
  github_owner      = "ggortsema"
  github_repository = "kharon"
  github_branch     = "main"
  flux_path         = "flux/clusters/dev"
  deploy_key_title  = "flux-terraform-dev"

  # Required for GitHub provider to create/manage deploy keys.
  github_token = get_env("GITHUB_TOKEN", "")
}
