# 3-tier app on EKS — Terraform conversion

Terraform version of the eksctl / kubectl / Helm workflow from "Kubernetes
real-world project with troubleshooting on AWS EKS" (Akhilesh Mishra).
Covers cluster creation through RDS, IRSA, the ALB controller, DNS, and TLS —
built as a root module that wires together seven child modules.

See **IMPLEMENTATION.md** for the full step-by-step build guide, written at
the same level of detail as the article itself.

## Layout

```
.
├── main.tf                  # wires the modules together + the DNS glue record
├── variables.tf
├── outputs.tf
├── providers.tf
├── versions.tf
├── backend.tf
├── terraform.tfvars.example
├── IMPLEMENTATION.md
└── modules/
    ├── networking/           # VPC, subnets, the ALB/NLB subnet tags
    ├── eks/                  # EKS cluster + managed node group
    ├── database/             # RDS Postgres, subnet group, security group
    ├── dns-tls/              # Route 53 zone + native ACM certificate
    ├── alb-controller/       # IRSA role + AWS Load Balancer Controller
    ├── cert-manager/         # optional — in-cluster cert-manager
    └── app/                  # namespace, secrets, migration job, deployments, ingress
```

## Module → article mapping

| Module | Replaces |
|---|---|
| `modules/networking` | the VPC `eksctl create cluster` builds behind the scenes |
| `modules/eks` | `eksctl create cluster` (cluster + managed node group) |
| `modules/database` | the DB subnet group, security group, and `aws rds create-db-instance` |
| `modules/alb-controller` | the OIDC provider / IAM role / `eksctl create iamserviceaccount` steps + `helm install aws-load-balancer-controller` |
| `modules/dns-tls` | `aws route53 create-hosted-zone` + the HTTPS post's cert issuance/import steps — done natively, see below |
| `modules/cert-manager` | the HTTPS post's steps 1–6, if you want cert-manager in-cluster too (optional) |
| `modules/app` | `namespace.yaml`, `secrets.yaml`, `configmap.yaml`, `migration_job.yaml`, `backend.yaml`, `frontend.yaml`, `ingress.yaml`, `ingress-with-tls.yaml` |
| root `main.tf` (the `aws_route53_record.app` resource) | the final A-record-alias step in both posts |

## Prerequisites

- Terraform >= 1.11
- An S3 bucket for state (versioning + SSE on), created once outside Terraform — fill its name into `backend.tf`
- AWS credentials that can create IAM roles/policies, VPCs, EKS clusters, and RDS instances
- `kubectl` for verification steps
- A domain you control, for `domain_name` — and, if it's a subdomain of a zone that already exists, that zone's name for `zone_name` (defaults already point at `auth.gavoksolutions.com` / `gavoksolutions.com`)

## Quick start

Full detail, with explanations at each stage, is in **IMPLEMENTATION.md**.
Short version:

1. `cp terraform.tfvars.example terraform.tfvars` — the example already has real values (`auth.gavoksolutions.com`), adjust if you're pointing this at something else.
2. `terraform init`
3. `terraform apply -target=module.networking -target=module.eks`
4. `terraform apply`
5. `terraform apply` again (or `-target=aws_route53_record.app`) once `kubectl get ingress -n 3-tier-app-eks` shows an ADDRESS.
6. If `create_hosted_zone = true`, take `terraform output route53_name_servers` and set them at your registrar. Not needed for the `auth.gavoksolutions.com` default — that zone already exists.

## Using a subdomain of an existing zone

`domain_name` and `zone_name` are separate on purpose. `domain_name` is the
FQDN the app is actually served on — it's what goes on the ACM certificate
and the ingress host rule. `zone_name` is which Route 53 hosted zone the
DNS and cert-validation records get created *in*. They're the same value
for a plain apex-domain deployment (the article's case) and diverge when
`domain_name` is a subdomain of a zone you already have — which is the
default here: `domain_name = "auth.gavoksolutions.com"`,
`zone_name = "gavoksolutions.com"`.

`create_hosted_zone` defaults to `false` to match: `gavoksolutions.com`
already has a hosted zone from the `eks-fullstack` project, so
`modules/dns-tls` looks it up with a `data` source instead of creating a
second, disconnected one. Two things worth doing before the first `apply`
against this default:

- Confirm the credentials/profile Terraform runs with actually reach the
  AWS account that zone lives in — a lookup against the wrong account just
  fails to find the zone rather than silently using the right one.
- Since the zone is shared with a live project, check nothing's already
  sitting on `auth.gavoksolutions.com`: `aws route53
  list-resource-record-sets --hosted-zone-id <id> --query
  "ResourceRecordSets[?contains(Name, 'auth')]"`.

If `zone_name` genuinely doesn't have a hosted zone yet, set
`create_hosted_zone = true` and it'll create one — same as before.

## What's deliberately different from the article

- **TLS**: native `aws_acm_certificate` + Route 53 DNS validation (`modules/dns-tls`) instead of cert-manager → export → `aws acm import-certificate`. An *imported* ACM certificate doesn't auto-renew — only the in-cluster secret does — so the article's HTTPS setup needs a manual re-import before every expiry. The native path renews itself. `modules/cert-manager` is still here, off by default (`enable_cert_manager = false`), if you want cert-manager running for other reasons.
- **DB credentials**: a generated `random_password`, not a literal string in the repo.
- **RDS security group**: scoped to the node security group only, never opened to `0.0.0.0/0` (that was a troubleshooting step in the article, not something to carry into the real config).
- **IRSA**: built through `terraform-aws-modules/iam//modules/iam-role-for-service-accounts-eks` instead of hand-written trust-policy JSON, in both `modules/alb-controller` and `modules/cert-manager`, and the service-account role-arn annotation is wired straight from each module's output.
- **Ingress cert ARN**: read from the ACM resource instead of pasted in, so it can't go stale on a redeploy.
- **Cluster access**: `access_entries` (current EKS module API) instead of the `aws-auth` ConfigMap.
- **No ExternalName Service for RDS**: the article adds a Kubernetes `ExternalName` Service so pods resolve the database through cluster DNS. This version skips that hop and puts the RDS address straight into the ConfigMap (`modules/app`) via `module.database.address` — one less moving part, at the cost of needing a `terraform apply` if the RDS endpoint ever changes. Add the ExternalName Service back into `modules/app/main.tf` if you'd rather have that indirection.

## Rough edges (same spirit as the article's own troubleshooting section)

- **Provider chicken-and-egg** on a from-scratch apply — the reason for the two-stage `apply` in the quick start. For a longer-lived setup, splitting this into a "cluster" state and a "platform" state removes the issue entirely.
- **`kubernetes_manifest.letsencrypt_issuer`** (optional, `modules/cert-manager`) needs the cert-manager CRDs to exist before Terraform can plan it. First time through: `terraform apply -target='module.cert_manager[0].helm_release.this'`, then the full apply.
- **`engine_version = "16"`** on the RDS instance lets AWS resolve a specific minor; expect a harmless one-time diff after the first apply.
- Module/chart versions (`terraform-aws-modules/eks/aws ~> 21.24`, the IAM submodule `~> 5.0`, the ALB controller and cert-manager chart versions) are current as of writing — `terraform init -upgrade` and check the registries before locking these in for the long term.
