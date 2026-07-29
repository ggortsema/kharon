include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/vpc/aws?version=5.21.0"
}

locals {
  root       = read_terragrunt_config(find_in_parent_folders("root.hcl"))
  cidr_block = "10.40.0.0/16"
}

inputs = {
  name = "${local.root.locals.project}-${local.root.locals.environment}-vpc"
  cidr = local.cidr_block

  azs             = ["${local.root.locals.aws_region}a", "${local.root.locals.aws_region}b", "${local.root.locals.aws_region}c"]
  private_subnets = ["10.40.1.0/24", "10.40.2.0/24", "10.40.3.0/24"]
  public_subnets  = ["10.40.101.0/24", "10.40.102.0/24", "10.40.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.root.locals.common_tags
}
