variable "zone_name" {
  description = "Route 53 hosted zone to use — the registered/delegated domain, e.g. gavoksolutions.com"
  type        = string
}

variable "record_name" {
  description = "Fully-qualified name the app is served on. Equal to zone_name for an apex-domain deployment, or a subdomain of it, e.g. auth.gavoksolutions.com"
  type        = string
}

variable "subject_alternative_names" {
  description = "Extra SANs for the ACM certificate, if any"
  type        = list(string)
  default     = []
}

variable "create_hosted_zone" {
  type    = bool
  default = true
}

variable "aws_region" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
