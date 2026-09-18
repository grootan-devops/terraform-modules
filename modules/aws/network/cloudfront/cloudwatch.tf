resource "aws_cloudwatch_log_group" "this" {
  name                        = "/aws/cloudfront/${local.rendered_name}"
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  kms_key_id                  = coalesce(var.cloudwatch_logs.kms_key_arn, var.kms_key_arn)
  log_group_class             = "STANDARD"
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled

  tags = merge(local.tags, { Name = "/aws/cloudfront/${local.rendered_name}" })
}

resource "aws_cloudwatch_log_delivery_source" "this" {
  name         = "${local.rendered_name}-cloudfront"
  region       = "us-east-1"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this.arn
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  name          = "${local.rendered_name}-cloudfront"
  region        = "us-east-1"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.this.arn
  }
}

resource "aws_cloudwatch_log_delivery" "this" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.this.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this.arn
  region                   = "us-east-1"

  record_fields = [
    "date", "time", "c-ip", "cs-method", "cs(Host)", "cs-uri-stem",
    "cs-uri-query", "x-host-header", "sc-status", "cs-protocol", "time-taken",
    "timestamp", "DistributionId", "cs(User-Agent)", "x-edge-result-type",
    "time-to-first-byte", "ssl-protocol", "ssl-cipher", "cs-protocol-version"
  ]
}
