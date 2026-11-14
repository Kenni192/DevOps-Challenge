terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.60" }
  }

  # Partial config: bucket/key/region/table are supplied at `terraform init -backend-config=...`
  backend "s3" {
    encrypt = true
  }
}
