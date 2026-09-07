variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as a resource-name prefix and tag"
  type        = string
  default     = "three-tier-eks"
}

variable "environment" {
  description = "dev/staging/prod — controls Multi-AZ, deletion protection, final-snapshot, and NAT gateway defaults"
  type        = string
  default     = "dev"
}

variable "cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "domain_name" {
  description = "Fully-qualified name the app is served on — the ACM certificate and the ingress host rule both use this"
  type        = string
  default     = "auth.gavoksolutions.com"
}

variable "zone_name" {
  description = "Route 53 hosted zone to use. Equals domain_name for an apex-domain deployment; set to the parent domain when domain_name is a subdomain of a zone that already exists. gavoksolutions.com already has a hosted zone from eks-fullstack, so this defaults to the parent domain rather than domain_name."
  type        = string
  default     = "gavoksolutions.com"
}

variable "create_hosted_zone" {
  description = "false to look up an existing Route 53 zone via data source instead of creating one. False by default here since the gavoksolutions.com zone already exists — flip to true only if zone_name genuinely has no hosted zone yet."
  type        = bool
  default     = false
}

variable "acm_subject_alternative_names" {
  description = "Extra SANs for the ACM certificate, if any. Empty by default — a www. prefix doesn't mean much for a subdomain like auth.gavoksolutions.com."
  type        = list(string)
  default     = []
}

variable "app_namespace" {
  type    = string
  default = "3-tier-app-eks"
}

variable "db_name" {
  type    = string
  default = "postgres"
}

variable "db_username" {
  type    = string
  default = "postgresadmin"
}

variable "db_instance_class" {
  description = "Graviton (t4g) by default — switch to db.t3.small if unavailable in your region/engine combo"
  type        = string
  default     = "db.t4g.small"
}

variable "db_multi_az" {
  description = "Multi-AZ RDS roughly doubles the instance cost — leave false for dev"
  type        = bool
  default     = false
}

variable "backend_image" {
  type    = string
  default = "livingdevopswithakhilesh/devopsdozo:backend-latest"
}

variable "frontend_image" {
  type    = string
  default = "livingdevopswithakhilesh/devopsdozo:frontend-latest"
}

variable "enable_cert_manager" {
  description = "Also stand up the optional in-cluster cert-manager module (modules/cert-manager) alongside the native ACM path"
  type        = bool
  default     = false
}

variable "acme_email" {
  description = "Contact email for Let's Encrypt — only used when enable_cert_manager = true"
  type        = string
  default     = "changeme@example.com"
}
