output "glue_role_arn" {
  value = aws_iam_role.glue_role.arn
}

output "sfn_role_arn" {
  value = aws_iam_role.sfn_role.arn
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_role.arn
}