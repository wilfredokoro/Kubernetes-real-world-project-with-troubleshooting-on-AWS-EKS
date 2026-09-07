output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this once the cluster exists to point kubectl at it"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

output "rds_endpoint" {
  value = module.database.endpoint
}

output "acm_certificate_arn" {
  value = module.dns_tls.certificate_arn
}

output "route53_name_servers" {
  description = "Only populated if create_hosted_zone = true — set these at your registrar"
  value       = module.dns_tls.name_servers
}

output "app_url" {
  value = "https://${var.domain_name}"
}
