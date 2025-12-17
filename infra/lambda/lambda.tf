# infra/lambda/lambda.tf
#
# Deploys Lambda only. SNS subscription & permission are handled at root level.
locals {
  lambda_name     = var.lambda_function_name
  lambda_zip_path = "${path.module}/deploy/lambda_package.zip"
}

# Package Lambda code (ZIP)
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/deploy"
  output_path = local.lambda_zip_path
}

# Lambda function definition
resource "aws_lambda_function" "post_ingest" {
  function_name = local.lambda_name
  role          = var.lambda_role_arn
  handler       = "handler.lambda_handler"
  runtime       = var.runtime
  filename      = data.archive_file.lambda_zip.output_path
  timeout       = 900

  environment {
    variables = {
      PROJECT_NAME  = var.project
      ENV           = var.env
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }

  tags = {
    Project = var.project
    Env     = var.env
  }
}

output "lambda_function_name" {
  value = aws_lambda_function.post_ingest.function_name
}

output "lambda_function_arn" {
  value = aws_lambda_function.post_ingest.arn
}