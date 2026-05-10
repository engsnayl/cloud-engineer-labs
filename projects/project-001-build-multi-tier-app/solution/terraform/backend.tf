terraform {
  backend "s3" {
    bucket         = "multi-tier-app-tfstate-340752829546"
    key            = "project-001/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "multi-tier-app-tf-locks"
  }
}
