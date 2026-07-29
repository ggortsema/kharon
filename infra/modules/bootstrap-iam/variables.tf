variable "aws_account_id" {
  description = "AWS account ID used for IAM/OIDC principals"
  type        = string
}

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

variable "tags" {
  description = "Tags applied to IAM resources"
  type        = map(string)
  default     = {}
}
