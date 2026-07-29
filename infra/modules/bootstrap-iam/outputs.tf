output "github_actions_role_arn" {
  description = "ARN of GitHub Actions OIDC role"
  value       = aws_iam_role.github_actions.arn
}
