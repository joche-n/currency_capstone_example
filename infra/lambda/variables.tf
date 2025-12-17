# infra/lambda/variables.tf
#
# Inputs for Lambda deployment.
# Takes the role ARN from the IAM module and optional environment variables.

variable "project" {
  type    = string
  default = "capstone-currency"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "lambda_role_arn" {
  description = "IAM role ARN for Lambda execution (from iam module)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name (for logs, artifacts, etc.)"
  type        = string
}

variable "sns_topic_arn" {
  description = "Optional SNS topic ARN for notifications"
  type        = string
  default     = ""
}

variable "lambda_function_name" {
  description = "Lambda function name"
  type        = string
  default     = "capstone-currency-lambda"
}

variable "runtime" {
  description = "Python runtime version"
  type        = string
  default     = "python3.12"
}