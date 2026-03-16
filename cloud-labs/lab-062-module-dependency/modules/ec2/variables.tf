variable "vpc_id" {
  description = "The VPC ID to deploy into"
  type        = string
}

variable "subnet_id" {
  description = "The subnet ID to deploy the EC2 instance into"
  type        = string
}
