resource "aws_instance" "app" {
  ami           = "ami-0eb260c4d5475b901"
  instance_type = "t3.micro"
  subnet_id     = var.subnet_id

  tags = {
    Name = "lab-ec2-instance"
  }
}
