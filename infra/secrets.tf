resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${var.project}/app-config"
  description             = "Application configuration for field-report-system Lambda"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    placeholder = "replace-me"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}
