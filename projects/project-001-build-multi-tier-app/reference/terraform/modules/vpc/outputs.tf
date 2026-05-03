# =============================================================================
# FILE: modules/vpc/outputs.tf
# PURPOSE: Exposes key resource IDs from the VPC module so other modules and
#          the root module can reference them.
#
# WHY OUTPUTS MATTER:
#   Terraform modules are like black boxes — the calling code can't see what's
#   inside unless you explicitly "output" it. For example, when we create
#   Security Groups in the root module, we need the VPC ID. Without this
#   output, the root module has no way to get it.
#
# HOW TO USE THESE:
#   In the root module (terraform/main.tf), after calling this module:
#     module.vpc.vpc_id            → gives the VPC ID
#     module.vpc.public_subnet_ids → gives a list of public subnet IDs
# =============================================================================

# -----------------------------------------------------------------------------
# VPC ID
# -----------------------------------------------------------------------------
# The unique identifier for the VPC. Nearly every other AWS networking resource
# needs this ID to know which VPC it belongs to (Security Groups, subnets, etc.).
output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

# -----------------------------------------------------------------------------
# PUBLIC SUBNET IDs
# -----------------------------------------------------------------------------
# A list of IDs for all public subnets. Used when launching load balancers,
# bastion hosts, or any resource that needs to be internet-facing.
# The [*] syntax collects the "id" attribute from ALL subnets created by count.
# Result looks like: ["subnet-abc123", "subnet-def456"]
output "public_subnet_ids" {
  description = "List of IDs for the public subnets"
  value       = aws_subnet.public[*].id
}

# -----------------------------------------------------------------------------
# PRIVATE SUBNET IDs
# -----------------------------------------------------------------------------
# A list of IDs for all private subnets. Used when launching backend services,
# databases, or any resource that should NOT be directly reachable from the internet.
output "private_subnet_ids" {
  description = "List of IDs for the private subnets"
  value       = aws_subnet.private[*].id
}

# -----------------------------------------------------------------------------
# NAT GATEWAY ID
# -----------------------------------------------------------------------------
# The ID of the NAT Gateway. Useful if other modules need to reference it
# (e.g., for monitoring or adding routes in additional route tables).
output "nat_gateway_id" {
  description = "The ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}

# -----------------------------------------------------------------------------
# INTERNET GATEWAY ID
# -----------------------------------------------------------------------------
# The ID of the Internet Gateway. Rarely needed outside the VPC module,
# but exposed in case other modules need to create routes through it.
output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}
