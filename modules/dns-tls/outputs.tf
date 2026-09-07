output "zone_id" {
  value = local.zone_id
}

output "zone_arn" {
  value = local.zone_arn
}

output "name_servers" {
  value = var.create_hosted_zone ? aws_route53_zone.app[0].name_servers : []
}

output "certificate_arn" {
  value = aws_acm_certificate_validation.app.certificate_arn
}

output "alb_zone_id" {
  description = "Hosted-zone ID to use as the alias target zone_id for an ALB in var.aws_region"
  value       = local.alb_zone_ids[var.aws_region]
}
