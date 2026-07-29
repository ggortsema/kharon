output "alb_controller_role_arn" {
  description = "ARN of IRSA role for aws-load-balancer-controller"
  value       = aws_iam_role.alb_controller.arn
}

output "external_dns_role_arn" {
  description = "ARN of IRSA role for external-dns"
  value       = aws_iam_role.external_dns.arn
}

output "flux_image_reflector_role_arn" {
  description = "ARN of IRSA role for Flux image-reflector-controller"
  value       = aws_iam_role.flux_image_reflector.arn
}
