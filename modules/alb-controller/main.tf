module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "3.2.2" # `helm search repo eks/aws-load-balancer-controller` to confirm current

  # Helm provider v3: set is a list of objects, not repeatable set {} blocks.
  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.aws_region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    # The annotation that's easy to leave commented out or pointing at the
    # wrong role — wired straight from the IRSA module output this time.
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.irsa.iam_role_arn
    },
    # The chart creates its own "alb" IngressClass by default (since v2.4.0)
    # — modules/app also creates one explicitly, so without this they
    # collide. Terraform-managed stays the single source of truth.
    {
      name  = "createIngressClassResource"
      value = "false"
    },
    # Without this, every `helm upgrade` regenerates the webhook's
    # self-signed CA and updates the ValidatingWebhookConfiguration
    # immediately — but the already-running controller pod keeps serving
    # the OLD cert until it restarts, so anything hitting the webhook in
    # that window fails with "certificate signed by unknown authority".
    # keepTLSSecret reuses the existing cert across upgrades instead of
    # rotating it every time. This only prevents it recurring on the next
    # upgrade — a mismatch already in progress still needs the controller
    # pod restarted once by hand (see chat).
    {
      name  = "keepTLSSecret"
      value = "true"
    }
  ]
}
