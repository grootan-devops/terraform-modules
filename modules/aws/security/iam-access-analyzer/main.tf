module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = {
    external = { suffix = "external", max_length = 255 }
    unused   = { suffix = "unused", max_length = 255 }
    internal = { suffix = "internal", max_length = 255 }
  }
}

resource "aws_organizations_aws_service_access" "this" {
  count = var.organization_admin.enabled && var.organization_admin.manage_trusted_access ? 1 : 0

  service_principal = "access-analyzer.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "this" {
  count = var.organization_admin.enabled ? 1 : 0

  account_id        = var.organization_admin.account_id
  service_principal = "access-analyzer.amazonaws.com"

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

resource "aws_accessanalyzer_analyzer" "external" {
  for_each = local.analyzer_created.external ? toset(local.regions) : toset([])

  region        = each.key
  analyzer_name = module.naming.names.external
  type          = "ORGANIZATION"

  tags = merge(module.naming.tags, { Name = module.naming.names.external })
}

resource "aws_accessanalyzer_analyzer" "unused" {
  count = local.analyzer_created.unused ? 1 : 0

  region        = local.unused_region
  analyzer_name = module.naming.names.unused
  type          = "ORGANIZATION_UNUSED_ACCESS"

  configuration {
    unused_access {
      unused_access_age = var.unused_access.unused_access_age

      dynamic "analysis_rule" {
        for_each = length(var.unused_access.exclusion_account_ids) + length(var.unused_access.exclusion_resource_tags) > 0 ? [true] : []
        content {
          dynamic "exclusion" {
            for_each = length(var.unused_access.exclusion_account_ids) > 0 ? [var.unused_access.exclusion_account_ids] : []
            content {
              account_ids = exclusion.value
            }
          }

          dynamic "exclusion" {
            for_each = length(var.unused_access.exclusion_resource_tags) > 0 ? [var.unused_access.exclusion_resource_tags] : []
            content {
              resource_tags = exclusion.value
            }
          }
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.unused })

  lifecycle {
    precondition {
      condition     = !contains(var.unused_access.exclusion_account_ids, local.account_id)
      error_message = "unused_access.exclusion_account_ids: not this account."
    }
  }
}

resource "aws_accessanalyzer_analyzer" "internal" {
  count = local.analyzer_created.internal ? 1 : 0

  region        = local.internal_region
  analyzer_name = module.naming.names.internal
  type          = "ORGANIZATION_INTERNAL_ACCESS"

  dynamic "configuration" {
    for_each = length(var.internal_access.inclusions) > 0 ? [true] : []
    content {
      internal_access {
        analysis_rule {
          dynamic "inclusion" {
            for_each = var.internal_access.inclusions
            content {
              account_ids    = inclusion.value.account_ids
              resource_arns  = inclusion.value.resource_arns
              resource_types = inclusion.value.resource_types
            }
          }
        }
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.internal })
}

resource "aws_accessanalyzer_archive_rule" "this" {
  for_each = local.archive_rule_instances

  region        = each.value.region
  analyzer_name = module.naming.names[each.value.analyzer]
  rule_name     = each.value.rule_name

  dynamic "filter" {
    for_each = each.value.filters
    content {
      criteria = filter.value.criteria
      eq       = filter.value.eq
      neq      = filter.value.neq
      contains = filter.value.contains
      exists   = filter.value.exists == null ? null : tostring(filter.value.exists)
    }
  }

  depends_on = [
    aws_accessanalyzer_analyzer.external,
    aws_accessanalyzer_analyzer.unused,
    aws_accessanalyzer_analyzer.internal,
  ]

  lifecycle {
    precondition {
      condition     = contains(local.analyzer_regions[each.value.analyzer], each.value.region)
      error_message = "archive_rules[*].region: a Region of the target analyzer."
    }
  }
}
