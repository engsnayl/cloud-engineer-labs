provider "aws" {
  region = "eu-west-1"

  default_tags {
    tags = {
      Project   = "cloud-engineer-labs"
      Component = "tfstate-bootstrap"
      ManagedBy = "terraform"
      Workspace = "bootstrap"
    }
  }
}
