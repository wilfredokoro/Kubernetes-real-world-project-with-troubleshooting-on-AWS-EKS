locals {
  cluster_name = "${var.project_name}-${var.environment}"

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

module "networking" {
  source = "./modules/networking"

  vpc_cidr           = var.vpc_cidr
  azs                = var.azs
  cluster_name       = local.cluster_name
  single_nat_gateway = var.environment != "prod"
  tags               = local.tags
}

module "eks" {
  source = "./modules/eks"

  cluster_name        = local.cluster_name
  cluster_version     = var.cluster_version
  vpc_id              = module.networking.vpc_id
  private_subnet_ids  = module.networking.private_subnet_ids
  node_instance_types = var.node_instance_types
  node_min_size       = var.node_min_size
  node_max_size       = var.node_max_size
  node_desired_size   = var.node_desired_size
  tags                = local.tags
}

module "database" {
  source = "./modules/database"

  cluster_name           = local.cluster_name
  vpc_id                 = module.networking.vpc_id
  private_subnet_ids     = module.networking.private_subnet_ids
  node_security_group_id = module.eks.node_security_group_id
  db_name                = var.db_name
  db_username            = var.db_username
  db_instance_class      = var.db_instance_class
  multi_az               = var.db_multi_az
  deletion_protection    = var.environment == "prod"
  skip_final_snapshot    = var.environment != "prod"
  tags                   = local.tags
}

# zone_name (gavoksolutions.com) is looked up as an existing zone by default;
# record_name (domain_name — auth.gavoksolutions.com) is what actually gets
# the A-record alias and the ACM certificate. See README.md's "Using a
# subdomain of an existing zone" section.
module "dns_tls" {
  source = "./modules/dns-tls"

  zone_name                 = var.zone_name
  record_name               = var.domain_name
  create_hosted_zone        = var.create_hosted_zone
  subject_alternative_names = var.acm_subject_alternative_names
  aws_region                = var.aws_region
  tags                      = local.tags
}

module "alb_controller" {
  source = "./modules/alb-controller"

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = module.networking.vpc_id
  aws_region        = var.aws_region
  tags              = local.tags

  depends_on = [module.eks]
}

# Optional — only stood up when enable_cert_manager = true. See the note at
# the top of modules/cert-manager/main.tf for why this isn't the default.
module "cert_manager" {
  source = "./modules/cert-manager"
  count  = var.enable_cert_manager ? 1 : 0

  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  hosted_zone_arn   = module.dns_tls.zone_arn
  hosted_zone_id    = module.dns_tls.zone_id
  domain_name       = var.domain_name
  aws_region        = var.aws_region
  acme_email        = var.acme_email
  tags              = local.tags

  depends_on = [module.eks]
}

module "app" {
  source = "./modules/app"

  namespace       = var.app_namespace
  backend_image   = var.backend_image
  frontend_image  = var.frontend_image
  db_address      = module.database.address
  db_name         = module.database.db_name
  db_username     = module.database.username
  db_password     = module.database.password
  certificate_arn = module.dns_tls.certificate_arn
  domain_name     = var.domain_name
  tags            = local.tags

  depends_on = [module.alb_controller]
}

# Glue resource: needs the zone from dns_tls and the ALB hostname from app,
# so it lives at the root rather than inside either module. Creates the
# "auth" record inside the gavoksolutions.com zone — no delegation needed,
# since a subdomain record inside its parent zone is just an ordinary record.
#
# NOTE: on a from-scratch apply, module.app's ingress hostname doesn't exist
# yet the first time Terraform reaches this resource — the AWS Load Balancer
# Controller reconciles the Ingress asynchronously. Re-run `terraform apply`
# (or `-target=aws_route53_record.app`) once `kubectl get ingress -n
# <app_namespace>` shows an ADDRESS.
resource "aws_route53_record" "app" {
  count   = module.app.ingress_hostname != null ? 1 : 0
  zone_id = module.dns_tls.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.app.ingress_hostname
    zone_id                = module.dns_tls.alb_zone_id
    evaluate_target_health = true
  }
}
