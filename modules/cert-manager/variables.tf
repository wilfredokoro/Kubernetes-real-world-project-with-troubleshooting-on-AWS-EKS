variable "cluster_name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "hosted_zone_arn" {
  type = string
}

variable "hosted_zone_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "acme_email" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
