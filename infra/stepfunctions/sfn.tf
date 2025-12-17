# infra/stepfunctions/sfn.tf
#
# Step Functions state machine that:
# 1) Starts Glue job (passes --S3_SCRIPT from input: $.script_s3)
# 2) Waits & polls GetJobRun until SUCCEEDED or FAILED (or max attempts)
# 3) Publishes a structured message to SNS with job outcome
#
# Example input to start execution:
# {
#   "script_s3": "s3://bucket/scripts/currency_bootstrap.py",
#   "arguments": {
#     "--S3_OUTPUT": "s3://bucket/raw/",
#     "--START_DATE": "2025-05-01",
#     "--END_DATE": "2025-10-31",
#     "--CURRENCIES": "USD,GBP,EUR,INR",
#     "--ACCESS_KEY": "REPLACE_WITH_SECRET_OR_SECRETS_MANAGER",
#     "--MAX_DAYS_PER_CALL": "365",
#     "--TempDir": "s3://bucket/temp/"
#   },
#   "metadata": { "triggered_by": "manual" }
# }

locals {
  sfn_def = jsonencode({
    Comment = "Start Glue job, poll for completion, publish result to SNS",
    StartAt = "Init",
    States = {
      # Initialize attempts and pass through script_s3 + metadata + arguments
      "Init" = {
        Type = "Pass",
        Parameters = {
          "attempts" = 0,
          "script_s3.$" = "$.script_s3",
          "metadata.$"  = "$.metadata",
          "arguments.$" = "$.arguments"
        },
        ResultPath = "$",
        Next = "StartGlue"
      },

      "StartGlue" = {
        Type = "Task",
        Resource = "arn:aws:states:::aws-sdk:glue:startJobRun",
        Parameters = {
          JobName = var.glue_job_name,
          Arguments = {
            "--S3_SCRIPT.$" = "$.script_s3",
            "--S3_OUTPUT.$" = "$.arguments.--S3_OUTPUT",
            "--START_DATE.$" = "$.arguments.--START_DATE",
            "--END_DATE.$" = "$.arguments.--END_DATE",
            "--CURRENCIES.$" = "$.arguments.--CURRENCIES",
            "--ACCESS_KEY.$" = "$.arguments.--ACCESS_KEY",
            "--MAX_DAYS_PER_CALL.$" = "$.arguments.--MAX_DAYS_PER_CALL",
            "--TempDir.$" = "$.arguments.--TempDir"
          }
        },
        ResultPath = "$.start_result",
        Catch = [
          {
            ErrorEquals = ["States.ALL"],
            Next = "PublishFailure"
          }
        ],
        Next = "WaitState"
      },

      "WaitState" = {
        Type = "Wait",
        Seconds = var.poll_interval_seconds,
        Next = "GetJobRun"
      },

      "GetJobRun" = {
        Type = "Task",
        Resource = "arn:aws:states:::aws-sdk:glue:getJobRun",
        Parameters = {
          JobName = var.glue_job_name,
          "RunId.$" = "$.start_result.JobRunId"
        },
        ResultPath = "$.get_job_result",
        Next = "CheckStatus"
      },

      "CheckStatus" = {
        Type = "Choice",
        Choices = [
          {
            Variable = "$.get_job_result.JobRun.JobRunState",
            StringEquals = "SUCCEEDED",
            Next = "PublishSuccess"
          },
          {
            Variable = "$.get_job_result.JobRun.JobRunState",
            StringEquals = "FAILED",
            Next = "PublishFailure"
          },
          {
            Variable = "$.get_job_result.JobRun.JobRunState",
            StringEquals = "STOPPED",
            Next = "PublishFailure"
          },
          {
            Variable = "$.get_job_result.JobRun.JobRunState",
            StringEquals = "TIMEOUT",
            Next = "PublishFailure"
          },
          {
            Variable = "$.get_job_result.JobRun.JobRunState",
            StringEquals = "RUNNING",
            Next = "WaitState"
          }
        ],
        Default = "CheckAttempts"
      },

      "CheckAttempts" = {
        Type = "Choice",
        Choices = [
          {
            Variable = "$.attempts",
            NumericGreaterThanEquals = var.max_attempts,
            Next = "PublishFailure"
          }
        ],
        Default = "IncrementAttempts"
      },

      "IncrementAttempts" = {
        Type = "Pass",
        Parameters = {
          "attempts.$" = "States.MathAdd($.attempts, 1)"
        },
        ResultPath = "$.attempts",
        Next = "WaitState"
      },

      "PublishSuccess" = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = var.sns_topic_arn,
          Message = {
            Project = var.project,
            Environment = var.env,
            "GlueJob.$" = "$.get_job_result.JobRun.JobName",
            Status = "SUCCEEDED",
            "RunId.$" = "$.get_job_result.JobRun.Id",
            "ScriptS3.$" = "$.script_s3",
            "StartTime.$" = "$.get_job_result.JobRun.StartedOn",
            "EndTime.$" = "$.get_job_result.JobRun.CompletedOn",
            "Metadata.$" = "$.metadata"
          }
        },
        End = true
      },

      "PublishFailure" = {
        Type = "Task",
        Resource = "arn:aws:states:::sns:publish",
        Parameters = {
          TopicArn = var.sns_topic_arn,
          Message = {
            Project = var.project,
            Environment = var.env,
            "GlueJob.$" = "$.get_job_result.JobRun.JobName",
            Status = "FAILED",
            "RunId.$" = "$.get_job_result.JobRun.Id",
            "ScriptS3.$" = "$.script_s3",
            "StartTime.$" = "$.get_job_result.JobRun.StartedOn",
            "EndTime.$" = "$.get_job_result.JobRun.CompletedOn",
            "ErrorMessage.$" = "$.get_job_result.JobRun.ErrorMessage",
            "Metadata.$" = "$.metadata"
          }
        },
        End = true
      }
    }
  })
}

resource "aws_sfn_state_machine" "glue_sm" {
  name       = "${var.project}-glue-sm-${var.env}"
  role_arn   = var.sfn_role_arn
  definition = local.sfn_def

  tags = {
    Project = var.project
    Env     = var.env
  }
}

output "sfn_arn" {
  value = aws_sfn_state_machine.glue_sm.arn
}

output "sfn_name" {
  value = aws_sfn_state_machine.glue_sm.name
}
