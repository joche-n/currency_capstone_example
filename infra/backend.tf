terraform {
  backend "s3" {
    bucket         = "capstone-project-currency-state-bucket" # created in bootstrap
    key            = "currency-infra/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "currency-capstone-lock-table" # created in bootstrap
    encrypt        = true
  }
}