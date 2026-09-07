module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0" # check the registry for the current major before applying

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = var.azs

  private_subnets = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i, az in var.azs : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  enable_nat_gateway   = true
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = true

  # The article's "subnet tag problem," handled up front: the AWS Load
  # Balancer Controller picks subnets for the ALB by these tags instead of
  # you tagging them by hand after an ingress fails to provision.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }

  tags = var.tags
}
