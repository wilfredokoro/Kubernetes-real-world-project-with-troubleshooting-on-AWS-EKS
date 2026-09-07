# Use a data source, not a resource, if this zone already exists — creating
# a duplicate zone here would just hand you a second set of name servers
# that don't match what's at your registrar. This matters more than usual
# when zone_name is a shared parent domain that another project's records
# already live in: a resource here would create an entirely separate,
# disconnected zone rather than adding to the real one.
resource "aws_route53_zone" "app" {
  count = var.create_hosted_zone ? 1 : 0
  name  = var.zone_name
  tags  = var.tags
}

data "aws_route53_zone" "app" {
  count = var.create_hosted_zone ? 0 : 1
  name  = var.zone_name
}

locals {
  zone_id  = var.create_hosted_zone ? aws_route53_zone.app[0].zone_id : data.aws_route53_zone.app[0].zone_id
  zone_arn = var.create_hosted_zone ? aws_route53_zone.app[0].arn : data.aws_route53_zone.app[0].arn

  # ALB alias-target hosted-zone IDs are a fixed per-region AWS constant, not
  # a property of any one load balancer — add a row if you deploy elsewhere.
  # (eu-west-1's value here matches the article's own change-batch —
  # Z32O12XQLNTSW2 — so the table is still current.)
  alb_zone_ids = {
    "us-east-1" = "Z35SXDOTRQ7X7K"
    "us-east-2" = "Z3AADJGX6KTTL2"
    "us-west-1" = "Z368ELLRRE2KJ0"
    "us-west-2" = "Z1H1FL5HABSF5"
    "eu-west-1" = "Z32O12XQLNTSW2"
  }
}

# Native ACM certificate with DNS validation through Route 53 — no export
# step, no manual import, and unlike an *imported* ACM certificate, this one
# renews itself. record_name can be the zone's apex or any subdomain of
# it — the validation records land in the same zone either way.
resource "aws_acm_certificate" "app" {
  domain_name               = var.record_name
  subject_alternative_names = var.subject_alternative_names
  validation_method          = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

resource "aws_route53_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "app" {
  certificate_arn         = aws_acm_certificate.app.arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}
