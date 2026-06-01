# ── CloudWatch log group ──────────────────────────────────────
# Created before the Lambda so logs are retained if Lambda is recreated.

resource "aws_cloudwatch_log_group" "process_report" {
  name              = "/aws/lambda/${var.project}-process-report"
  retention_in_days = 30
}

# ── Lambda function ───────────────────────────────────────────
# Placeholder zip — replaced by GitHub Actions on first deploy.
# The data source packages whatever is in lambda/process_report/
# at the time of terraform apply.

data "archive_file" "process_report" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/process_report"
  output_path = "${path.module}/../lambda/process_report.zip"
}

resource "aws_lambda_function" "process_report" {
  function_name    = "${var.project}-process-report"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 256
  filename         = data.archive_file.process_report.output_path
  source_code_hash = data.archive_file.process_report.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE    = aws_dynamodb_table.field_reports.name
      SNS_TOPIC_ARN     = aws_sns_topic.notifications.arn
      PHOTOS_BUCKET     = aws_s3_bucket.photos.bucket
      BEDROCK_MODEL_ID  = "anthropic.claude-3-haiku-20240307-v1:0"
      SECRET_NAME       = aws_secretsmanager_secret.app_config.name
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.process_report,
    aws_iam_role_policy.lambda_exec_policy
  ]
}
