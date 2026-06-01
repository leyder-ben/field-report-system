# ── REST API ──────────────────────────────────────────────────

resource "aws_api_gateway_rest_api" "field_report" {
  name        = "${var.project}-api"
  description = "Field Report System API"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# ── /reports resource ─────────────────────────────────────────

resource "aws_api_gateway_resource" "reports" {
  rest_api_id = aws_api_gateway_rest_api.field_report.id
  parent_id   = aws_api_gateway_rest_api.field_report.root_resource_id
  path_part   = "reports"
}

# ── POST /reports ─────────────────────────────────────────────

resource "aws_api_gateway_method" "post_reports" {
  rest_api_id      = aws_api_gateway_rest_api.field_report.id
  resource_id      = aws_api_gateway_resource.reports.id
  http_method      = "POST"
  authorization    = "NONE"
  api_key_required = false

  request_validator_id = aws_api_gateway_request_validator.body.id

  request_models = {
    "application/json" = aws_api_gateway_model.report_submission.name
  }
}

resource "aws_api_gateway_integration" "post_reports" {
  rest_api_id             = aws_api_gateway_rest_api.field_report.id
  resource_id             = aws_api_gateway_resource.reports.id
  http_method             = aws_api_gateway_method.post_reports.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.process_report.invoke_arn
}

# ── GET /reports ──────────────────────────────────────────────

resource "aws_api_gateway_method" "get_reports" {
  rest_api_id   = aws_api_gateway_rest_api.field_report.id
  resource_id   = aws_api_gateway_resource.reports.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "get_reports" {
  rest_api_id             = aws_api_gateway_rest_api.field_report.id
  resource_id             = aws_api_gateway_resource.reports.id
  http_method             = aws_api_gateway_method.get_reports.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.process_report.invoke_arn
}

# ── CORS — OPTIONS /reports ───────────────────────────────────
# Required for browser-based form submission from S3-hosted UI.

resource "aws_api_gateway_method" "options_reports" {
  rest_api_id   = aws_api_gateway_rest_api.field_report.id
  resource_id   = aws_api_gateway_resource.reports.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_reports" {
  rest_api_id = aws_api_gateway_rest_api.field_report.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.options_reports.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = "{\"statusCode\": 200}"
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.field_report.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.options_reports.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_200" {
  rest_api_id = aws_api_gateway_rest_api.field_report.id
  resource_id = aws_api_gateway_resource.reports.id
  http_method = aws_api_gateway_method.options_reports.http_method
  status_code = "200"

  depends_on = [
    aws_api_gateway_integration.options_reports,
    aws_api_gateway_method_response.options_200,
  ]

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,POST,OPTIONS'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}

# ── Request validation ────────────────────────────────────────

resource "aws_api_gateway_request_validator" "body" {
  rest_api_id          = aws_api_gateway_rest_api.field_report.id
  name                 = "validate-body"
  validate_request_body = true
}

resource "aws_api_gateway_model" "report_submission" {
  rest_api_id  = aws_api_gateway_rest_api.field_report.id
  name         = "ReportSubmission"
  content_type = "application/json"

  schema = jsonencode({
    "$schema" = "http://json-schema.org/draft-04/schema#"
    type      = "object"
    required  = ["tech_name", "job_site", "report_type"]
    properties = {
      tech_name   = { type = "string" }
      job_site    = { type = "string" }
      report_type = { type = "string" }
      equipment   = { type = "string" }
      notes       = { type = "string" }
      photo_key   = { type = "string" }
    }
  })
}

# ── Deployment and stage ──────────────────────────────────────

resource "aws_api_gateway_deployment" "prod" {
  rest_api_id = aws_api_gateway_rest_api.field_report.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.reports.id,
      aws_api_gateway_method.post_reports.id,
      aws_api_gateway_method.get_reports.id,
      aws_api_gateway_integration.post_reports.id,
      aws_api_gateway_integration.get_reports.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.prod.id
  rest_api_id   = aws_api_gateway_rest_api.field_report.id
  stage_name    = "prod"
}

# ── Lambda permission ─────────────────────────────────────────
# Allows API Gateway to invoke the Lambda function.

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_report.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.field_report.execution_arn}/*/*"
}

# Note: options_200 integration response depends on the mock integration
# being fully created first — explicit dependency prevents race condition.
