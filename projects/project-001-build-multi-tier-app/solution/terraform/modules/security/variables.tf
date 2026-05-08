variable "project_name" {
  description = "Project identifier used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security groups attach to"
  type        = string
}

variable "frontend_ingress_cidrs" {
  description = "CIDR blocks allowed to reach the frontend on 80/443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "backend_port" {
  description = "Port the backend tier listens on"
  type        = number
  default     = 8080
}

variable "database_port" {
  description = "Port the database tier listens on"
  type        = number
  default     = 5432
}
