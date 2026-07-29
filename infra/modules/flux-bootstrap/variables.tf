variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "aws_region" {
  description = "AWS region for the EKS cluster"
  type        = string
}

variable "github_owner" {
  description = "GitHub owner or organization"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "Git branch Flux should sync from"
  type        = string
  default     = "main"
}

variable "flux_path" {
  description = "Repository path Flux should reconcile"
  type        = string
  default     = "flux/clusters/dev"
}

variable "deploy_key_title" {
  description = "Title for the GitHub deploy key managed by Terraform"
  type        = string
  default     = "flux-terraform"
}

variable "github_token" {
  description = "GitHub token used by Terraform provider"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.github_token)) > 0
    error_message = "github_token must be set (for example via GITHUB_TOKEN env var)."
  }
}
