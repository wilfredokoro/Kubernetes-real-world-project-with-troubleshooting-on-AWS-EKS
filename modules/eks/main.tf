module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.24"

  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  endpoint_public_access = true

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  # v21 doesn't bootstrap these by default — without this block, nothing
  # installs the VPC CNI DaemonSet, so nodes join with no CNI plugin at all
  # and sit in NetworkPluginNotReady indefinitely. before_compute = true on
  # vpc-cni gets it running before the node group tries to come up, instead
  # of racing it.
  addons = {
    vpc-cni = {
      before_compute = true
    }
    kube-proxy = {}
    coredns    = {}
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  eks_managed_node_groups = {
    standard-workers = {
      instance_types = var.node_instance_types
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size

      # v21 changed the managed-node-group IMDS hop-limit default from 2 to
      # 1, which blocks pods from reaching IMDS — set it back to 2.
      metadata_options = {
        http_put_response_hop_limit = 2
      }
    }
  }

  tags = var.tags
}

# The EBS CSI driver's controller needs its own IAM permissions to
# create/attach/delete volumes — the node role alone isn't enough. This
# feeds into the addons block above, which makes it look like eks ->
# ebs_csi_irsa -> eks, but it isn't circular: oidc_provider_arn only depends
# on the cluster and its OIDC provider, never on addons or node groups.
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}

# EKS doesn't ship a default StorageClass on its own — without this, the
# driver installs but nothing can actually provision a volume through it.
# gp3 is cheaper and generally faster than gp2 at the same size.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }
  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"
  volume_binding_mode = "WaitForFirstConsumer"
  parameters = {
    type = "gp3"
  }

  depends_on = [module.eks]
}
