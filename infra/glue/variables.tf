# infra/glue/variables.tf
#
# Inputs for the Glue module. Provide bucket_name and glue_role_arn (from iam/glue_role).
# job_name: a stable name for the Glue job (used in Step Functions).
# You can tweak glue_version and max_capacity for your needs.

variable "project" {
  type    = string
  default = "capstone-currency"
}

variable "env" {
  type    = string
  default = "dev"
}

variable "bucket_name" {
  description = "S3 bucket name where scripts and raw data live (module.s3.bucket_name)"
  type        = string
}

variable "glue_role_arn" {
  description = "IAM role ARN for Glue (module.iam.glue_role_arn)"
  type        = string
}

variable "job_name" {
  description = "Name of the Glue job"
  type        = string
  default     = "capstone-currency-job"
}

variable "glue_version" {
  description = "Glue version for the job"
  type        = string
  default     = "3.0"
}

variable "max_capacity" {
  description = "Max capacity for Glue Python shell (DPU or number for worker type)"
  type        = number
  default     = 0.0625 # 1/16 DPU
}