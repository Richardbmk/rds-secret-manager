# Terraform Settings Block
terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31"
    }
      helm = {
      source = "hashicorp/helm"
      version = "2.13.2"
    }
  }
}

# Terraform Provider Block
provider "aws" {
  region = var.region
}