output "frontend_sg_id" {
  description = "ID of the frontend security group"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "ID of the backend security group"
  value       = aws_security_group.backend.id
}

output "database_sg_id" {
  description = "ID of the database security group"
  value       = aws_security_group.database.id
}
