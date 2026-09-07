# S3-native locking (use_lockfile) replaces the classic S3 + DynamoDB pair —
# no lock table to provision or pay for. Requires Terraform >= 1.11.
# Create the bucket once, out of band, with versioning and SSE enabled,
# before the first `terraform init`.
terraform {
  backend "s3" {
    bucket       = "gavok202-tfstate"
    key          = "3-tier-app-eks/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
