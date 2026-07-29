variable "github_owner" {
  description = "GitHub org/user that owns the repository"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
}

variable "github_actions_role_name" {
  description = "IAM role name used by GitHub Actions OIDC"
  type        = string
}

variable "alb_controller_role_name" {
  description = "IAM role name for aws-load-balancer-controller IRSA"
  type        = string
}

variable "external_dns_role_name" {
  description = "IAM role name for external-dns IRSA"
  type        = string
}

variable "flux_image_reflector_role_name" {
  description = "IAM role name for Flux image-reflector-controller IRSA"
  type        = string
}

variable "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN"
  type        = string
}

variable "eks_oidc_provider_url" {
  description = "EKS OIDC provider URL path without scheme, e.g. oidc.eks.us-east-1.amazonaws.com/id/XXXX"
  type        = string
}

variable "tags" {
  description = "Tags applied to IAM resources"
  type        = map(string)
  default     = {}
}

variable "aws_account_id" {
  description = "AWS account ID used for IAM/OIDC principals"
  type        = string
}
