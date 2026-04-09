# =============================================================================
# outputs.tf — Lab 092
#
# These outputs expose the instance IDs after terraform apply.
# The seeding script reads these dynamically rather than hardcoding IDs,
# which would break on every terraform destroy/apply cycle.
# =============================================================================

output "prod_web_instance_ids" {
  description = "Instance IDs of the production web servers"
  value       = aws_instance.prod_web[*].id
}

output "dev_web_instance_id" {
  description = "Instance ID of the dev web server"
  value       = aws_instance.dev_web.id
}

output "dev_worker_instance_ids" {
  description = "Instance IDs of the dev worker instances"
  value       = aws_instance.dev_worker[*].id
}

output "all_instance_ids" {
  description = "All instance IDs in this lab — used by the seeding script"
  value = concat(
    aws_instance.prod_web[*].id,
    [aws_instance.dev_web.id],
    aws_instance.dev_worker[*].id
  )
}

output "all_instance_ids_csv" {
  description = "Comma-separated list of all instance IDs — for easy copy-paste into AWS CLI commands"
  value = join(",", concat(
    aws_instance.prod_web[*].id,
    [aws_instance.dev_web.id],
    aws_instance.dev_worker[*].id
  ))
}

output "region" {
  description = "AWS region this lab is deployed into"
  value       = "eu-west-2"
}
