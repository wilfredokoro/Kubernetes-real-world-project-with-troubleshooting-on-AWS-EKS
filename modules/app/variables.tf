variable "namespace" {
  type = string
}

variable "backend_image" {
  type = string
}

variable "frontend_image" {
  type = string
}

variable "db_address" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "certificate_arn" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
