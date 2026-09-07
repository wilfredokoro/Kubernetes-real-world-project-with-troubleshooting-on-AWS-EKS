variable "vpc_cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "cluster_name" {
  description = "Used only to build the kubernetes.io/cluster/<name> subnet tags the ALB controller looks for"
  type        = string
}

variable "single_nat_gateway" {
  description = "true = one shared NAT Gateway (cheaper); false = one per AZ (more resilient)"
  type        = bool
  default     = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
