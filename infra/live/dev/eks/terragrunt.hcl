include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "tfr:///terraform-aws-modules/eks/aws?version=21.24.0"
}

dependency "vpc" {
  config_path = "../vpc"
}

locals {
  root = read_terragrunt_config(find_in_parent_folders("root.hcl"))
}

inputs = {
  name               = "${local.root.locals.project}-${local.root.locals.environment}-eks"
  kubernetes_version = "1.30"
  enable_cluster_creator_admin_permissions = false

  access_entries = {
    cluster_creator = {
      principal_arn = "arn:aws:iam::${local.root.locals.aws_account_id}:user/kharon-local-dev"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
    gha_admin = {
      principal_arn = "arn:aws:iam::${local.root.locals.aws_account_id}:role/kharon-gha-terraform-plan-apply"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  endpoint_public_access = true

  security_group_additional_rules = {
    egress_all = {
      description = "Allow control plane egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "egress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  enable_irsa = true

  eks_managed_node_groups = {
    workers = {
      name            = "workers"
      use_name_prefix = false
      min_size       = 3
      max_size       = 3
      desired_size   = 3
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"
    }
  }

  addons = {
    coredns = {
      before_compute = true
    }
    kube-proxy = {
      before_compute = true
    }
    vpc-cni = {
      before_compute = true
    }
  }

  tags = local.root.locals.common_tags
}
