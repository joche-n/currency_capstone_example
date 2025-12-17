# infra/iam/glue_role.tf
#
# IAM role for AWS Glue. Grants:
# - read access to S3 bucket (scripts + raw + tmp prefixes)
# - write access to S3 bucket for processed/tmp output
# - CloudWatch Logs permissions to put logs
# Keep this role narrow by providing the exact bucket ARN from module input.

data "aws_iam_policy_document" "glue_assume" {
  statement {
    effect = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_role" {
  name               = "${var.project}-glue-role-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
  tags = { Project = var.project, Env = var.env }
}

# Policy: S3 read/write limited to the bucket and its objects
resource "aws_iam_policy" "glue_s3_policy" {
  name = "${var.project}-glue-s3-policy-${var.env}"
  description = "Allow Glue job to read scripts and write/read raw data in S3"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "AllowListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [var.s3_bucket_arn]
      },
      {
        Sid = "AllowObjectOps"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObjectVersion",
          "s3:PutObjectAcl"
        ]
        Resource = ["${var.s3_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_attach_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_s3_policy.arn
}

# Allow Glue to write logs to CloudWatch
resource "aws_iam_policy" "glue_logs" {
  name        = "${var.project}-glue-logs-${var.env}"
  description = "CloudWatch Logs permissions for Glue"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = ["arn:aws:logs:*:*:*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_attach_logs" {
  role       = aws_iam_role.glue_role.name
  policy_arn = aws_iam_policy.glue_logs.arn
}