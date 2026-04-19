provider "aws" {
  region = "eu-west-2"
}

resource "aws_vpc" "app" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "app-vpc" }
}

resource "aws_vpc" "db" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "db-vpc" }
}

resource "aws_vpc_peering_connection" "app_to_db" {
  vpc_id      = aws_vpc.app.id
  peer_vpc_id = aws_vpc.db.id
  auto_accept = true
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.app.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.db.id
  cidr_block = "10.0.2.0/24"
}

resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.db.id
}

resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.app.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.db.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
}
