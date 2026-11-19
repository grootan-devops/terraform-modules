resource "aws_ebs_default_kms_key" "this" {
  for_each = local.ebs_default_keys

  region  = each.key
  key_arn = each.value
}

resource "aws_ebs_encryption_by_default" "this" {
  for_each = local.per_region.ebs_encryption

  region  = each.key
  enabled = true

  depends_on = [aws_ebs_default_kms_key.this]
}

resource "aws_ec2_instance_metadata_defaults" "this" {
  for_each = local.per_region.metadata_defaults

  region                      = each.key
  http_tokens                 = "required"
  http_put_response_hop_limit = var.instance_metadata_defaults.http_put_response_hop_limit
}

resource "aws_ebs_snapshot_block_public_access" "this" {
  for_each = local.per_region.snapshot_block

  region = each.key
  state  = var.ebs_snapshot_block_public_access.state
}

resource "aws_ec2_image_block_public_access" "this" {
  for_each = local.per_region.ami_block

  region = each.key
  state  = "block-new-sharing"
}

resource "aws_ec2_serial_console_access" "this" {
  for_each = local.per_region.serial_console_block

  region  = each.key
  enabled = false
}

resource "aws_vpc_block_public_access_options" "this" {
  for_each = local.per_region.vpc_block

  region                      = each.key
  internet_gateway_block_mode = var.vpc_block_public_access.mode
}

module "api_gateway_role" {
  source = "../../security/iam-role"
  count  = var.api_gateway_logging.enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "apigw-logs"
  tags                     = var.tags
  description              = "API Gateway pushes execution and access logs to CloudWatch Logs."
  permissions_boundary_arn = var.permissions_boundary_arn
  managed_policy_arns      = ["${local.arn_prefix}:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"]
  trust = {
    services = ["apigateway.${module.naming.dns_suffix}"]
  }
}

resource "aws_api_gateway_account" "this" {
  for_each = local.per_region.api_gateway

  region              = each.key
  cloudwatch_role_arn = module.api_gateway_role[0].arn
}
