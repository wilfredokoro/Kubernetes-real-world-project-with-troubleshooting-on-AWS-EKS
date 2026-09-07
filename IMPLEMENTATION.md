# Implementing the 3-tier app on EKS with Terraform — step by step

This walks through building the same thing the article does — a React
frontend, Flask backend, and private RDS Postgres on EKS, behind an ALB with
HTTPS on your own domain — using the module set in this repo instead of
eksctl/kubectl/Helm run by hand. Same end state, same order of operations,
far fewer individual commands because `terraform apply` is doing the work
that eksctl, `aws rds create-db-instance`, `kubectl apply -f`, and
`helm install` did individually in the original.

---

## Part 1 — Cluster, database, and the app

### Step 1: Install the tooling

You need:

- Terraform >= 1.11 (1.11+ is required for the S3 native state-locking backend in `backend.tf`)
- AWS CLI, configured with credentials that can create VPCs, IAM roles/policies, EKS clusters, and RDS instances
- `kubectl` — Terraform builds the cluster, but you still want it for verification
- A domain you control

You do **not** need `eksctl` or the Helm CLI — the `helm_release` and EKS
module resources replace both.

### Step 2: Create the state bucket

One-time, outside Terraform:

```
aws s3api create-bucket --bucket YOUR-COMPANY-tfstate --region us-east-1
aws s3api put-bucket-versioning --bucket YOUR-COMPANY-tfstate \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket YOUR-COMPANY-tfstate \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

Put the bucket name in `backend.tf`, replacing `REPLACE_ME-tfstate`.

### Step 3: Set your variables

```
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. Every variable has a default, including
`domain_name` (`auth.gavoksolutions.com`) and `zone_name`
(`gavoksolutions.com`) — the app is served on the subdomain, DNS and
cert-validation records get created inside the parent zone, which already
exists from the `eks-fullstack` project. `create_hosted_zone = false`
matches that: `modules/dns-tls` looks the zone up instead of creating it.

Before the first apply, worth confirming two things about that zone since
it's shared with a live project:

```
# credentials Terraform will use can actually see the zone
aws route53 list-hosted-zones-by-name --dns-name gavoksolutions.com

# nothing's already using the subdomain
aws route53 list-resource-record-sets --hosted-zone-id <id> \
  --query "ResourceRecordSets[?contains(Name, 'auth')]"
```

Deploying somewhere else entirely — a domain with no existing zone — set
`create_hosted_zone = true` and leave `zone_name` matching `domain_name`;
that's the article's plain apex-domain case and needs nothing else changed.

### Step 4: Initialize

```
terraform init
```

This downloads the `aws`, `kubernetes`, `helm`, and `random` providers plus
the community `vpc`, `eks`, and `iam-role-for-service-accounts-eks` modules
that the local modules wrap.

### Step 5: Stand up networking and the cluster

```
terraform apply -target=module.networking -target=module.eks
```

This is the Terraform equivalent of the article's `eksctl create cluster`
command — it creates the VPC (with the subnet tags the ALB controller needs
already applied, so you never hit the article's "subnet tag problem"), the
EKS control plane, and the managed node group. It takes 10–15 minutes,
same as the eksctl version.

Why this has to be its own `apply` rather than folded into the next step:
the `kubernetes` and `helm` providers in `providers.tf` authenticate against
`module.eks`'s outputs, and on a completely fresh account those outputs
don't exist until the cluster does. Terraform can't finish planning
anything that depends on those providers until there's a real cluster to
point them at. Once the cluster exists, every later `apply` in this
directory can be a single, ordinary `terraform apply` — this two-stage
dance is only needed the first time.

### Step 6: Point kubectl at the new cluster

This replaces the article's "Setting up the cluster config to access the
cluster from the local machine" section:

```
terraform output -raw configure_kubectl | sh
kubectl config current-context
kubectl get nodes
kubectl get ns
```

You should see your managed node group's instances as `Ready` nodes, same
as the article's `kubectl get node` check.

### Step 7: Apply everything else

```
terraform apply
```

One command now covers everything the article does across the rest of both
posts:

- **`modules/database`** — the DB subnet group, the security group scoped to
  the node security group, and the RDS Postgres instance. Same as the
  article's "Creating RDS Postgres instance" section, minus the manual
  `$SG_ID`/`$NODE_SG` shell variables — Terraform wires the security group
  reference directly.
- **`modules/app`**'s ConfigMap and Secret — same fields as the article's
  `configmap.yaml`/`secrets.yaml`, but Terraform base64-encodes the Secret
  for you instead of `echo 'x' | base64`.
- **`modules/app`**'s migration Job — runs once, the same role as the
  article's `migration_job.yaml`.
- **`modules/app`**'s backend and frontend Deployments and Services — same
  shape as `backend.yaml`/`frontend.yaml`.
- **`modules/alb-controller`** — the OIDC-provider/IRSA-role/service-account
  chain from the article's "Set up an OIDC provider" through "Installing the
  AWS Load Balancer Controller with Helm" sections, plus the Helm release
  itself.
- **`modules/dns-tls`** — the Route 53 hosted zone and a native ACM
  certificate, validated via DNS records Terraform creates and waits on.
  This is where this version diverges most from the article — see Part 2
  below for why.
- **`modules/app`**'s Ingress — same annotations as the article's
  `ingress-with-tls.yaml` (scheme, target-type, health check path, listen
  ports, SSL redirect), with the certificate ARN read live from the ACM
  resource instead of pasted in by hand.

Expect this `apply` to take a while — RDS alone is typically 5–10 minutes,
and ACM's DNS validation has to actually propagate before Terraform will
consider the certificate issued.

### Step 8: Verify the migration and the app pods

Same checks as the article's post-migration and post-deployment sections:

```
kubectl get jobs -n 3-tier-app-eks
kubectl logs job/database-migration -n 3-tier-app-eks
kubectl get deployment -n 3-tier-app-eks
kubectl get pods -n 3-tier-app-eks
kubectl get svc -n 3-tier-app-eks
```

If the migration Job's logs show a connection error here, it's almost
always the RDS security group or the wrong `DB_HOST` — check
`terraform output rds_endpoint` against what's in the ConfigMap.

### Step 9: Optional local sanity check via port-forward

The same trick the article uses before the ingress exists, still useful
here as a quick check independent of DNS/ALB:

```
kubectl port-forward -n 3-tier-app-eks svc/backend 8000:8000 &
curl http://localhost:8000/api/topics

kubectl port-forward -n 3-tier-app-eks svc/frontend 8080:80 &
```

Then open `127.0.0.1:8080`.

### Step 10: Confirm the ALB came up

```
kubectl get ingress -n 3-tier-app-eks
kubectl describe ingress 3-tier-app-ingress -n 3-tier-app-eks
```

Same as the article's ingress verification — you're looking for an
`ADDRESS` column populated with an ALB hostname. If it's blank after a few
minutes, check the controller's own logs, same as the article does:

```
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller
```

### Step 11: Point DNS at the ALB

```
terraform apply
```

Run it again now that step 10 confirms the Ingress has an address. This
picks up `module.app.ingress_hostname` and creates the apex A-record alias
(`aws_route53_record.app` in root `main.tf`) — the Terraform equivalent of
the article's `aws route53 change-resource-record-sets` call.

If `create_hosted_zone = true`, this is also the point to take
`terraform output route53_name_servers` and set them at your domain
registrar, same as the article's "copy the name servers" step. DNS
propagation is the same wait either way — give it a few minutes, then
`https://your-domain` should resolve straight to HTTPS with a valid,
browser-trusted certificate.

---

## Part 2 — HTTPS

The article's second post spends ten steps getting cert-manager to issue a
certificate, exporting it out of the Kubernetes Secret it lands in, and
manually importing it into ACM so the ALB can use it. That entire chain
already happened in Step 7 above, inside `modules/dns-tls`, as two
resources: `aws_acm_certificate` and `aws_acm_certificate_validation`. No
export, no `awk`-splitting a combined cert file into `cert.pem`/`chain.pem`/
`key.pem`, no `aws acm import-certificate`.

The reason not to replicate the article's exact chain: an ACM certificate
that's been *imported* doesn't auto-renew. cert-manager will happily renew
the certificate sitting in the Kubernetes Secret, but nothing re-runs the
export-and-import steps against ACM, so the certificate the ALB is actually
serving quietly goes stale unless someone repeats those steps by hand
before every expiry. A native ACM certificate, requested and validated by
Terraform, renews itself with no ongoing action required.

### Step 12 (optional): Turn on cert-manager anyway

If you want cert-manager running in-cluster regardless — for certificates
on services that aren't behind this ALB, or because you want to standardize
on it across clusters — `modules/cert-manager` is here, just not wired in
by default:

```
# in terraform.tfvars
enable_cert_manager = true
acme_email           = "you@example.com"
```

```
terraform apply -target='module.cert_manager[0].helm_release.this'
terraform apply
```

The two-step apply here is the same class of issue as Step 5: the
`ClusterIssuer` is a `kubernetes_manifest` resource, and that resource type
validates against the CRD's schema at *plan* time — so the cert-manager
CRDs (installed by the Helm chart) need to already exist before Terraform
can even plan the `ClusterIssuer`, let alone create it. Once the chart's
installed, the rest applies normally.

Verify with:

```
kubectl get pods -n cert-manager
kubectl get clusterissuer letsencrypt-prod
```

---

## Troubleshooting

Same failure modes the article calls out, same fixes, adjusted for where
each thing now lives:

| Symptom | Where to look |
|---|---|
| Migration Job / backend can't reach the DB | `modules/database`'s security group only allows the node security group on 5432 — confirm the pod's node is actually in that node group, and that `DB_HOST` in the ConfigMap matches `terraform output rds_endpoint` |
| Ingress has no `ADDRESS` | `kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller` — usually an IAM permission gap (check `modules/alb-controller`'s IRSA role) or a subnet tagging issue (shouldn't happen here since `modules/networking` sets the tags up front, but worth confirming with `aws ec2 describe-subnets` if it does) |
| ALB up but 503s on every request | Target group health checks failing — check the Deployments' readiness (`kubectl get pods -n 3-tier-app-eks`) and that `alb.ingress.kubernetes.io/healthcheck-path` matches a route your app actually serves |
| ACM certificate stuck in `PENDING_VALIDATION` | The DNS validation CNAME records haven't propagated yet, or `create_hosted_zone` is pointed at the wrong zone — `aws acm describe-certificate` and compare the validation records against `dig` |
| `ClusterIssuer`/`Certificate` stuck (only relevant if `enable_cert_manager = true`) | `kubectl describe certificaterequest`, `kubectl describe order`, `kubectl describe challenge` — same diagnostic chain the article walks through |
| First `terraform apply` fails on a `kubernetes`/`helm` provider error | You skipped Step 5 — the cluster has to exist before those providers can authenticate |

## Tearing down

`terraform destroy` works, but do it in the same spirit as bring-up — the
app and DNS layers first, cluster last, since IAM roles the ALB controller
and cert-manager depend on need to outlive the Kubernetes objects that
reference them:

```
terraform destroy -target=module.app -target=aws_route53_record.app
terraform destroy
```

If `db_multi_az`/`deletion_protection` are on, or `create_hosted_zone` is
`true` and you want to keep the zone, adjust the targets accordingly before
the final destroy.
