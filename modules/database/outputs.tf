output "address" {
  value = aws_db_instance.postgres.address
}

output "endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "username" {
  value = var.db_username
}

output "password" {
  value     = random_password.master.result
  sensitive = true
}

output "db_name" {
  value = var.db_name
}

output "security_group_id" {
  value = aws_security_group.rds.id
}
