module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    { export = { suffix = "findings-export", max_length = 128 } },
    { for key in keys(var.filters) : "filter-${key}" => { suffix = key, max_length = 64 } },
  )
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  purpose            = "guardduty"
  tags               = var.tags
  kms                = merge(var.kms, { create = var.kms.create && local.export_enabled })
  service_statements = local.kms_service_statements
}

resource "aws_guardduty_detector" "this" {
  for_each = toset(local.detector_regions)

  region                       = each.key
  enable                       = true
  finding_publishing_frequency = var.detector.finding_publishing_frequency

  tags = module.naming.tags
}

resource "aws_guardduty_detector_feature" "this" {
  for_each = local.feature_instances

  region      = each.value.region
  detector_id = aws_guardduty_detector.this[each.value.region].id
  name        = each.value.name
  status      = local.feature_catalog[each.value.name].enabled ? "ENABLED" : "DISABLED"

  dynamic "additional_configuration" {
    for_each = local.feature_catalog[each.value.name].additional

    content {
      name   = additional_configuration.value.name
      status = additional_configuration.value.enabled ? "ENABLED" : "DISABLED"
    }
  }
}

resource "aws_guardduty_organization_configuration" "this" {
  for_each = toset(local.organization_regions)

  region                           = each.key
  detector_id                      = aws_guardduty_detector.this[each.key].id
  auto_enable_organization_members = local.auto_enable_members
}

resource "aws_guardduty_organization_configuration_feature" "this" {
  for_each = local.organization_feature_instances

  region      = each.value.region
  detector_id = aws_guardduty_detector.this[each.value.region].id
  name        = each.value.name
  auto_enable = local.feature_catalog[each.value.name].enabled ? local.auto_enable_members : "NONE"

  dynamic "additional_configuration" {
    for_each = local.feature_catalog[each.value.name].additional

    content {
      name        = additional_configuration.value.name
      auto_enable = additional_configuration.value.enabled ? local.auto_enable_members : "NONE"
    }
  }

  depends_on = [aws_guardduty_organization_configuration.this]
}

resource "aws_guardduty_filter" "this" {
  for_each = local.filter_instances

  region      = each.value.region
  detector_id = aws_guardduty_detector.this[each.value.region].id
  name        = module.naming.names["filter-${each.value.key}"]
  description = var.filters[each.value.key].description
  action      = var.filters[each.value.key].action
  rank        = local.filter_ranks[each.value.key]

  finding_criteria {
    dynamic "criterion" {
      for_each = local.filter_criteria[each.value.key]

      content {
        field                 = criterion.key
        equals                = criterion.value.equals
        not_equals            = criterion.value.not_equals
        matches               = criterion.value.matches
        not_matches           = criterion.value.not_matches
        greater_than          = criterion.value.greater_than
        greater_than_or_equal = criterion.value.greater_than_or_equal
        less_than             = criterion.value.less_than
        less_than_or_equal    = criterion.value.less_than_or_equal
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["filter-${each.value.key}"] })
}
