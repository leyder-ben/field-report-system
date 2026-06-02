variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "prod"
}

variable "project" {
  description = "Project name — used in resource naming"
  type        = string
  default     = "field-report"
}

variable "alert_email" {
  description = "Email address for SNS office notifications"
  type        = string
}
