# infra/glue/glue.tf

locals {
  # Keep Glue scripts in a clear prefix in the bucket
  scripts_prefix = "scripts/"
  bootstrap_key  = "${local.scripts_prefix}currency_bootstrap.py"
}

# Upload the bootstrap runner script from the module folder to S3.
# Terraform will re-upload whenever the file content changes (etag).
# aws_s3_object or aws_s3_bucket_object that uploads currency_bootstrap.py
resource "aws_s3_object" "bootstrap_script" {
  bucket = var.bucket_name
  key    = "scripts/currency_bootstrap.py" # or glue/scripts/... if you changed it
  source = "${path.module}/scripts/currency_bootstrap.py"

  # REMOVE this if present:
  # force_destroy = true

  # keep whatever else you had, e.g.
  content_type           = "text/x-python"
  server_side_encryption = "AES256"
  etag                   = filemd5("${path.module}/scripts/currency_bootstrap.py")

  tags = {
    Project = var.project
    Env     = var.env
  }
}

# Glue Python Shell job that launches the bootstrap script.
# The bootstrap reads a --S3_SCRIPT argument to locate the "real" script
# (e.g., currency.py you’ll later upload/version elsewhere).
resource "aws_glue_job" "currency" {
  name     = var.job_name
  role_arn = var.glue_role_arn

  command {
    name            = "pythonshell"
    python_version  = "3.9"
    script_location = "s3://${var.bucket_name}/${local.bootstrap_key}"
  }

  # Default args; you can override any at StartJobRun.
  default_arguments = {
    "--TempDir"          = "s3://${var.bucket_name}/tmp/"
    "--S3_SCRIPT"        = ""                                  # pass actual script at runtime
    "--S3_OUTPUT"        = "s3://${var.bucket_name}/raw"
    "--CURRENCIES"       = "USD,GBP,EUR,INR"
    "--MAX_DAYS_PER_CALL"= "365"
    "--START_DATE"       = "2023-01-01"
    "--BASE"             = "USD"
    #  Do NOT hardcode secrets in code or Terraform:
     "--ACCESS_KEY"     = "ABCD"  # prefer Secrets Manager or SSM
  }

  max_capacity = var.max_capacity
  glue_version = var.glue_version

  execution_property {
    max_concurrent_runs = 1
  }

  tags = {
    Project = var.project
    Env     = var.env
  }

  # Ensure the S3 object is uploaded before the job is created/updated
  depends_on = [aws_s3_object.bootstrap_script]
}