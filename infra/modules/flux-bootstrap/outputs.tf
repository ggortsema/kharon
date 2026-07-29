output "deploy_key_id" {
  description = "GitHub deploy key ID used by Flux"
  value       = github_repository_deploy_key.flux.id
}

output "flux_namespace" {
  description = "Namespace where Flux is installed"
  value       = "flux-system"
}
