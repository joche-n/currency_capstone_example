output "glue_job_name" {
  value = aws_glue_job.currency.name
}

output "bootstrap_s3_path" {
  value = "s3://${var.bucket_name}/${local.bootstrap_key}"
}