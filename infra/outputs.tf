output "api_gateway_url" {
  description = "Base URL for the Field Report API"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/reports"
}

output "ui_bucket_website_url" {
  description = "URL of the mobile web form"
  value       = "http://${aws_s3_bucket_website_configuration.ui.website_endpoint}"
}

output "dynamodb_table_name" {
  description = "DynamoDB table name — shared with Projects B and C"
  value       = aws_dynamodb_table.field_reports.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB table ARN — used by Projects B and C"
  value       = aws_dynamodb_table.field_reports.arn
}

output "sns_topic_arn" {
  description = "SNS topic ARN — shared with Projects B and C"
  value       = aws_sns_topic.notifications.arn
}

output "lambda_function_name" {
  description = "Lambda function name — used by GitHub Actions deploy"
  value       = aws_lambda_function.process_report.function_name
}

output "photos_bucket_name" {
  description = "S3 bucket for photo attachments"
  value       = aws_s3_bucket.photos.bucket
}
