include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../../modules/iam"
}

dependency "eks" {
  config_path = "../eks"
}

locals {
  root = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  alb_controller_role_name = "kharon-aws-load-balancer-controller"
  external_dns_role_name   = "kharon-external-dns"
  flux_image_reflector_role_name = "kharon-flux-image-reflector"

  eks_oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  eks_oidc_provider_url = dependency.eks.outputs.oidc_provider

  tags = local.root.locals.common_tags
}
