data "aws_organizations_organization" "current" {}

module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    { for k in local.policy_keys : k => { suffix = replace(k, "_", "-"), max_length = 128 } },
    { policy_delegation = { suffix = "policy-delegation", max_length = 128 } },
  )
}

resource "aws_organizations_organization" "this" {
  count = var.organization.manage ? 1 : 0

  feature_set          = "ALL"
  enabled_policy_types = local.managed_policy_types

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [aws_service_access_principals]

    precondition {
      condition     = var.organization.allow_policy_type_disable || length(local.policy_types_to_disable) == 0
      error_message = "Refusing to disable enabled policy types: ${join(", ", sort(tolist(local.policy_types_to_disable)))}."
    }
  }
}

resource "aws_organizations_aws_service_access" "this" {
  for_each = local.trusted_access_principals

  service_principal = each.value
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each = var.delegated_administrators

  account_id        = each.value.account_id
  service_principal = each.value.service_principal

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_organizations_resource_policy" "this" {
  count = var.policy_management_delegation.enabled ? 1 : 0

  content = local.delegation_policy_content

  tags = merge(module.naming.tags, { Name = module.naming.names.policy_delegation })
}

resource "aws_iam_organizations_features" "this" {
  count = var.root_access_management.enabled ? 1 : 0

  enabled_features = var.root_access_management.features

  depends_on = [aws_organizations_aws_service_access.this]
}

resource "aws_organizations_policy" "this" {
  for_each = local.policies

  name        = local.policy_names[each.key]
  description = each.value.description
  type        = each.value.type
  content     = each.value.content

  tags = merge(module.naming.tags, { Name = local.policy_names[each.key] })

  depends_on = [aws_organizations_organization.this]

  lifecycle {
    precondition {
      condition     = length(each.value.content) <= local.policy_size_limits[each.value.type]
      error_message = "Policy ${each.key}: over the ${each.value.type} size limit."
    }

    precondition {
      condition     = each.value.type != "SERVICE_CONTROL_POLICY" || try(length(local.policy_statements[each.key]) > 0, false)
      error_message = "SCP ${each.key}: no statements."
    }

    precondition {
      condition     = each.value.type != "RESOURCE_CONTROL_POLICY" || try(local.rcp_shape_valid[each.key], false)
      error_message = "RCP ${each.key}: Deny, Principal * and RCP-supported actions only."
    }
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.this[each.value.policy_key].id
  target_id = each.value.target_id

  depends_on = [aws_organizations_organization.this]

  lifecycle {
    precondition {
      condition     = contains(tolist(local.effective_policy_types), each.value.type)
      error_message = "Policy type ${each.value.type} is not enabled on the root."
    }

    precondition {
      condition     = length(local.attachments_per_type_target["${each.value.type}|${each.value.target_id}"]) <= try(local.policy_attachment_limits[each.value.type], 10)
      error_message = "Too many ${each.value.type} policies on ${each.value.target_id}."
    }
  }
}
