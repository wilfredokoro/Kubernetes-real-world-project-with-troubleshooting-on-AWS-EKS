output "ingress_hostname" {
  # null, not an error, until the AWS Load Balancer Controller has actually
  # provisioned the ALB and populated the Ingress's status — that happens
  # asynchronously, well after the Ingress object itself is created.
  value = try(kubernetes_ingress_v1.app.status[0].load_balancer[0].ingress[0].hostname, null)
}

output "namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}
