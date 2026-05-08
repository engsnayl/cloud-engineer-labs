# Frontend tier receives traffic from the internet
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-${var.environment}-frontend"
  description = "Frontend tier — public-facing"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-frontend-sg"
    Tier = "frontend"
  }
}

# Backend tier receives traffic only from the frontend SG
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-${var.environment}-backend"
  description = "Backend tier — accessible only from frontend SG"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-backend-sg"
    Tier = "backend"
  }
}

# Database tier receives traffic only from the backend SG
resource "aws_security_group" "database" {
  name        = "${var.project_name}-${var.environment}-database"
  description = "Database tier — accessible only from backend SG"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-database-sg"
    Tier = "database"
  }
}

# --- Ingress rules ---

resource "aws_security_group_rule" "frontend_http" {
  type              = "ingress"
  security_group_id = aws_security_group.frontend.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = var.frontend_ingress_cidrs
  description       = "HTTP from approved CIDRs"
}

resource "aws_security_group_rule" "frontend_https" {
  type              = "ingress"
  security_group_id = aws_security_group.frontend.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = var.frontend_ingress_cidrs
  description       = "HTTPS from approved CIDRs"
}

resource "aws_security_group_rule" "backend_from_frontend" {
  type                     = "ingress"
  security_group_id        = aws_security_group.backend.id
  from_port                = var.backend_port
  to_port                  = var.backend_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.frontend.id
  description              = "Backend port from frontend tier only"
}

resource "aws_security_group_rule" "database_from_backend" {
  type                     = "ingress"
  security_group_id        = aws_security_group.database.id
  from_port                = var.database_port
  to_port                  = var.database_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.backend.id
  description              = "Database port from backend tier only"
}

# --- Egress rules ---
# Each tier allowed full outbound. Default SG egress would cover this, but
# making it explicit is clearer when reading the module standalone.

resource "aws_security_group_rule" "frontend_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.frontend.id
  from_port         = 0 # Port range. 0 to 0 is a special case meaning "all ports" but only when combined with protocol = "-1"
  to_port           = 0
  protocol          = "-1" # "-1" means all protocols
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

resource "aws_security_group_rule" "backend_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.backend.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

resource "aws_security_group_rule" "database_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.database.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}
