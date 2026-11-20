data "aws_regions" "opt_in" {
  count = local.export_enabled ? 1 : 0

  all_regions = true

  filter {
    name   = "opt-in-status"
    values = ["opted-in", "not-opted-in"]
  }
}

module "destination_policy" {
  source = "../../core/policy-document"

  statements = local.destination_statements
}

module "kms_policy" {
  source = "../../core/policy-document"

  statements        = local.kms_service_statements
  default_resources = ["*"]
}

resource "aws_guardduty_publishing_destination" "this" {
  for_each = local.export_regions

  region           = each.key
  detector_id      = aws_guardduty_detector.this[each.key].id
  destination_type = "S3"
  destination_arn  = local.destination_arn
  kms_key_arn      = local.kms_key_arn

  tags = merge(module.naming.tags, { Name = module.naming.names.export })
}
