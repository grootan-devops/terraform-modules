terraform {
  required_version = ">= 1.17.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.8.1"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.73.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
