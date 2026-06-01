resource "aws_dynamodb_table" "field_reports" {
  name         = "field-reports"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "report_id"
  range_key    = "submitted_at"

  attribute {
    name = "report_id"
    type = "S"
  }

  attribute {
    name = "submitted_at"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name        = "field-reports"
    Description = "Shared table for Projects A B and C"
  }
}
