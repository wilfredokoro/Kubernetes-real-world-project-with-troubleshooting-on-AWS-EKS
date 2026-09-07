terraform {
  required_version = ">= 1.11.0" # 1.11+ needed for S3 native state locking (see backend.tf)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0" # floor required by terraform-aws-modules/eks/aws ~> 21.x
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0" # v3 bumped the plugin protocol version and changed some resource
      # defaults, but — unlike helm's v3 — doesn't appear to replace
      # resource blocks (metadata{}, spec{}, container{}, etc.) with
      # object/list attributes. Run `terraform validate` after this
      # change; if something in modules/app still breaks, paste it.
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0" # v3 rewrote set{}/kubernetes{} as list/object attributes — code here targets v3 syntax
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
