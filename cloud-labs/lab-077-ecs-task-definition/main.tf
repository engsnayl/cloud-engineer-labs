# ECS Task Definition Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_ecs_cluster" "main" {
  name = "production"
}

resource "aws_ecs_task_definition" "payment_api" {
  family                   = "payment-api"
  # BUG 1: Fargate requires specific network mode
  network_mode             = "bridge"  # Should be "awsvpc" for Fargate
  requires_compatibilities = ["FARGATE"]
  # BUG 2: Missing execution role (needed to pull images)
  # execution_role_arn       = aws_iam_role.ecs_execution.arn
  # BUG 3: CPU and memory not set at task level (required for Fargate)
  
  container_definitions = jsonencode([
    {
      name      = "payment-api"
      image     = "payment-api:latest"
      # BUG 4: Missing port mappings
      essential = true
      environment = [
        { name = "DB_HOST", value = "db.internal" },
        { name = "DB_PORT", value = "5432" }
      ]
      # BUG 5: No log configuration
    }
  ])
}

resource "aws_ecs_service" "payment_api" {
  name            = "payment-api"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.payment_api.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.app.id]
    security_groups = [aws_security_group.app.id]
  }
}

resource "aws_iam_role" "ecs_execution" {
  name = "ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }
resource "aws_subnet" "app" { vpc_id = aws_vpc.main.id; cidr_block = "10.0.1.0/24" }
resource "aws_security_group" "app" { name = "app-sg"; vpc_id = aws_vpc.main.id }
