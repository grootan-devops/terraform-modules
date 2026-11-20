module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names       = { for key in keys(var.filters) : key => { suffix = key, max_length = 64 } }
}

resource "aws_inspector2_delegated_admin_account" "this" {
  for_each = var.organization_admin.enabled ? toset(local.regions) : toset([])

  region     = each.key
  account_id = var.organization_admin.account_id

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

resource "aws_inspector2_organization_configuration" "this" {
  for_each = local.org_enabled ? toset(local.regions) : toset([])

  region = each.key

  auto_enable {
    ec2             = local.auto_enable.ec2
    ecr             = local.auto_enable.ecr
    lambda          = local.auto_enable.lambda
    lambda_code     = local.auto_enable.lambda_code
    code_repository = local.auto_enable.code_repository
  }
}

resource "aws_inspector2_enabler" "admin" {
  for_each = local.org_enabled && var.organization_configuration.activate_admin_account ? toset(local.regions) : toset([])

  region         = each.key
  account_ids    = [local.account_id]
  resource_types = local.resource_types
}

resource "aws_inspector2_member_association" "this" {
  for_each = local.member_associations

  region     = each.value.region
  account_id = each.value.account_id

  lifecycle {
    precondition {
      condition     = each.value.account_id != local.account_id
      error_message = "member_account_ids: not the administrator account."
    }
  }
}

resource "aws_inspector2_enabler" "members" {
  for_each = local.org_enabled && length(local.member_account_ids) > 0 ? toset(local.regions) : toset([])

  region         = each.key
  account_ids    = local.member_account_ids
  resource_types = local.resource_types

  depends_on = [aws_inspector2_member_association.this]
}

resource "aws_inspector2_filter" "this" {
  for_each = local.filter_instances

  region      = each.value.region
  name        = module.naming.names[each.value.key]
  action      = var.filters[each.value.key].action
  description = var.filters[each.value.key].description
  reason      = var.filters[each.value.key].reason

  filter_criteria {
    dynamic "severity" {
      for_each = var.filters[each.value.key].severity
      content {
        comparison = severity.value.comparison
        value      = severity.value.value
      }
    }

    dynamic "finding_type" {
      for_each = var.filters[each.value.key].finding_type
      content {
        comparison = finding_type.value.comparison
        value      = finding_type.value.value
      }
    }

    dynamic "resource_type" {
      for_each = var.filters[each.value.key].resource_type
      content {
        comparison = resource_type.value.comparison
        value      = resource_type.value.value
      }
    }

    dynamic "vulnerability_id" {
      for_each = var.filters[each.value.key].vulnerability_id
      content {
        comparison = vulnerability_id.value.comparison
        value      = vulnerability_id.value.value
      }
    }

    dynamic "aws_account_id" {
      for_each = var.filters[each.value.key].aws_account_id
      content {
        comparison = aws_account_id.value.comparison
        value      = aws_account_id.value.value
      }
    }

    dynamic "resource_tags" {
      for_each = var.filters[each.value.key].resource_tags
      content {
        comparison = "EQUALS"
        key        = resource_tags.value.key
        value      = resource_tags.value.value
      }
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names[each.value.key] })
}
