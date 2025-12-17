# infra/iam/sfn_role.tf
#
# Role assumed by Step Functions to call AWS SDK operations (StartJobRun, GetJobRun)
# and to invoke Lambda. Scope actions to Glue & Lambda; currently Lambda ARN can be passed in.
# Tighten Resource ARNs whenever you have exact ARNs.

data "aws_iam_policy_document" "sfn_assume" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn_role" {
  name               = "${var.project}-sfn-role-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
  tags = { Project = var.project, Env = var.env }
}

# Policy document allowing Step Functions to start and poll Glue jobs and invoke Lambda
resource "aws_iam_policy" "sfn_policy" {
  name        = "${var.project}-sfn-policy-${var.env}"
  description = "Allow Step Functions to start/poll Glue jobs, invoke Lambda, and publish SNS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "GlueStartAndGet",
        Effect = "Allow",
        Action = [
          "glue:StartJobRun",
          "glue:GetJobRun",
          "glue:GetJobRuns"
        ],
        Resource = var.glue_job_name != "" ? "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${var.glue_job_name}" : "*"
      },
      {
        Sid = "InvokeLambda",
        Effect = "Allow",
        Action = [
          "lambda:InvokeFunction"
        ],
        Resource = var.lambda_function_arn
      },
      {
        Sid = "PublishToSNS",
        Effect = "Allow",
        Action = [
          "sns:Publish"
        ],
        Resource = "*"
      },
      {
        Sid = "CloudWatchLogs",
        Effect = "Allow",
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

# Need to pull account / region for precise GLUE ARN (data sources)
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_role_policy_attachment" "sfn_attach_policy" {
  role       = aws_iam_role.sfn_role.name
  policy_arn = aws_iam_policy.sfn_policy.arn
}