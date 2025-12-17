# infra/iam/variables.tf
#
# Inputs for the IAM module. Provide s3_bucket_arn from the s3 module outputs.
# lambda_function_arn is optional here (used to scope Step Functions permission).
# Adjust values/ARNS in root module when wiring everything together.

variable "project" {
  type    = string
  default = "capstone-currency"
}

variable "env" {
  type    = string
  default = "dev"
}

# The data bucket ARN (e.g. module.s3.bucket_arn)
variable "s3_bucket_arn" {
  type = string
}

# The Lambda function ARN the Step Function will call (optional at creation time).
# If you don't have it yet, you can set this to "*" temporarily and tighten later.
variable "lambda_function_arn" {
  type    = string
  default = "*"
}

# (Optional) If you want to scope Glue actions to a specific Glue job, pass job ARN/name
variable "glue_job_name" {
  type    = string
  default = ""
}

variable "aws_region" {
  type = string
  default = ""
}