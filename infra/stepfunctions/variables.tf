# infra/stepfunctions/variables.tf
#
# Inputs:
#  - project/env: tagging
#  - glue_job_name: glue job to run
#  - sfn_role_arn: IAM role ARN assumed by Step Functions (must allow glue:* and sns:Publish)
#  - sns_topic_arn: ARN of SNS topic to publish results to (required)
#  - poll_interval_seconds: how long to wait between Glue job status checks
#  - max_attempts: optional safety guard to avoid infinite loops in broken cases

variable "project" {
  type    = string
  default = "capstone-currency"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "glue_job_name" {
  description = "Name of the Glue job to start (e.g. capstone-currency-job)"
  type        = string
}

variable "sfn_role_arn" {
  description = "IAM role ARN for Step Functions (must be assumable by states.amazonaws.com)"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for publishing Glue run results (required)"
  type        = string
}

variable "poll_interval_seconds" {
  description = "Wait seconds between GetJobRun polls"
  type        = number
  default     = 20
}

variable "max_attempts" {
  description = "Maximum number of polls to attempt before failing"
  type        = number
  default     = 150
}