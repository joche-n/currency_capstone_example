# infra/iam/lambda_role.tf
#
# Role for Lambda function that runs post-ingest work (SNS publish, SSM read, optionally Secrets Manager)
# Attach AWSLambdaBasicExecutionRole for CloudWatch logging and add SSM/SNS permissions.

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project}-lambda-role-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags = { Project = var.project, Env = var.env }
}

# Basic execution role for logging
resource "aws_iam_role_policy_attachment" "lambda_basic_exec" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline policy to allow SSM read (for script pointer), SNS publish (notify), and optionally SecretsManager read
resource "aws_iam_policy" "lambda_extra" {
  name        = "${var.project}-lambda-extra-${var.env}"
  description = "Allow Lambda to read SSM params and publish SNS messages (and optionally SecretsManager)"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowSSMRead",
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath"
        ],
        Resource = "*"
      },
      {
        Sid = "AllowSNSPublish",
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = "*"
      },
      {
        Sid = "AllowSecretsRead",
        Effect = "Allow",
        Action = [
          "secretsmanager:GetSecretValue"
        ],
        Resource = "*"  # tighten to specific secret ARN later
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_extra_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_extra.arn
}