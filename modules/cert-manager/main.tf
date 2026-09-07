# OPTIONAL module — only instantiated when enable_cert_manager = true at the
# root. Only needed if you want cert-manager running in-cluster for
# something other than the public ALB endpoint — modules/dns-tls already
# covers that with fewer moving parts and real auto-renewal.

module "irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-cert-manager"

  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = [var.hosted_zone_arn]

  oidc_providers = {
    main = {
      provider_arn               = var.oidc_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }

  tags = var.tags
}

resource "helm_release" "this" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = "v1.21.1" # check for a newer patch before applying

  # Helm provider v3: set is a list of objects, not repeatable set {} blocks.
  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
    {
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = module.irsa.iam_role_arn
    }
  ]
}

# kubernetes_manifest validates against the CRD's schema at plan time, so
# this needs the cert-manager CRDs to already exist. On a first apply, run
# `terraform apply -target='module.cert_manager[0].helm_release.this'`
# before the full apply.
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.acme_email
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            selector = {
              dnsZones = [var.domain_name]
            }
            dns01 = {
              route53 = {
                region       = var.aws_region
                hostedZoneID = var.hosted_zone_id
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.this]
}
