resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.namespace
  }
}

resource "random_password" "flask_secret" {
  length  = 32
  special = false
}

resource "kubernetes_config_map_v1" "app" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    DB_HOST     = var.db_address
    DB_NAME     = var.db_name
    DB_PORT     = "5432"
    FLASK_APP   = "run.py"
    FLASK_DEBUG = "0"
  }
}

# Plain Secret, same shape as the article's — Terraform base64-encodes this
# for you, so there's no `echo 'x' | base64` step to run by hand. If you're
# already running External Secrets Operator elsewhere, this is a natural
# swap for an ExternalSecret pointing at Vault/Secrets Manager instead.
resource "kubernetes_secret_v1" "db" {
  metadata {
    name      = "db-secrets"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  data = {
    DB_USERNAME  = var.db_username
    DB_PASSWORD  = var.db_password
    SECRET_KEY   = random_password.flask_secret.result
    DATABASE_URL = "postgresql://${var.db_username}:${var.db_password}@${var.db_address}:5432/${var.db_name}"
  }
  type = "Opaque"
}

# migrate.sh, baked into the image at /app/migrate.sh, is this app's actual
# migration entrypoint — confirmed by exec'ing into a running backend pod
# and reading it directly, not guessed. It's idempotent: `flask db init`
# only if migrations/ doesn't exist yet (that's the "Path doesn't exist"
# error every attempt hit — flask db upgrade alone never runs init), then
# upgrade, an auto-generated migration if the models changed, upgrade
# again, then seed_data.py only if the topics table is still empty. Its
# seed-data check needs DB_HOST/DB_PORT/DB_USERNAME/DB_PASSWORD/DB_NAME —
# already covered by the ConfigMap and Secret below, nothing extra needed.
resource "kubernetes_job_v1" "db_migration" {
  metadata {
    name      = "database-migration"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    backoff_limit = 3
    template {
      metadata {}
      spec {
        restart_policy = "Never"
        container {
          name    = "migration"
          image   = var.backend_image
          command = ["bash", "/app/migrate.sh"]
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.app.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.db.metadata[0].name
            }
          }
        }
      }
    }
  }
  # Back to a hard gate now that the command is verified rather than
  # guessed — wait_for_completion = false was a temporary way to stop this
  # one job from blocking RDS/addons/the rest of the app while the real
  # command was still unknown. If migrate.sh itself ever needs debugging
  # again, flip this back to false rather than let it block everything a
  # second time.
  wait_for_completion = true
  timeouts {
    create = "5m"
  }
}

resource "kubernetes_deployment_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = { app = "backend" }
  }
  spec {
    replicas = 2
    selector {
      match_labels = { app = "backend" }
    }
    template {
      metadata {
        labels = { app = "backend" }
      }
      spec {
        container {
          name  = "backend"
          image = var.backend_image
          port {
            container_port = 8000
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.app.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret_v1.db.metadata[0].name
            }
          }
          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
  depends_on = [kubernetes_job_v1.db_migration]
}

resource "kubernetes_service_v1" "backend" {
  metadata {
    name      = "backend"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    selector = { app = "backend" }
    port {
      port        = 8000
      target_port = 8000
    }
  }
}

resource "kubernetes_deployment_v1" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    labels    = { app = "frontend" }
  }
  spec {
    replicas = 2
    selector {
      match_labels = { app = "frontend" }
    }
    template {
      metadata {
        labels = { app = "frontend" }
      }
      spec {
        container {
          name  = "frontend"
          image = var.frontend_image
          port {
            container_port = 80
          }
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "frontend" {
  metadata {
    name      = "frontend"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }
  spec {
    selector = { app = "frontend" }
    port {
      port        = 80
      target_port = 80
    }
  }
}

resource "kubernetes_ingress_class_v1" "alb" {
  metadata {
    name = "alb"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "false"
    }
  }
  spec {
    controller = "ingress.k8s.aws/alb"
  }
}

resource "kubernetes_ingress_v1" "app" {
  metadata {
    name      = "3-tier-app-ingress"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
    annotations = {
      "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"      = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path" = "/"
      "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
      "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
      # Pulled straight from the ACM resource — no stale ARNs to sed in
      # after a re-apply.
      "alb.ingress.kubernetes.io/certificate-arn" = var.certificate_arn
    }
  }
  spec {
    ingress_class_name = kubernetes_ingress_class_v1.alb.metadata[0].name
    rule {
      host = var.domain_name
      http {
        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.backend.metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.frontend.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
