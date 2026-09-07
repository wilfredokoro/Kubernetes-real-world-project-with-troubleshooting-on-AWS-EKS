output "iam_role_arn" {
  value = module.irsa.iam_role_arn
}

output "helm_release_status" {
  value = helm_release.this.status
}
