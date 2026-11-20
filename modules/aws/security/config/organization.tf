resource "aws_organizations_aws_service_access" "this" {
  for_each = var.organization_admin.enabled && var.organization_admin.manage_trusted_access ? local.config_principals : toset([])

  service_principal = each.key
}

resource "aws_organizations_delegated_administrator" "this" {
  for_each = var.organization_admin.enabled ? local.config_principals : toset([])

  account_id        = var.organization_admin.account_id
  service_principal = each.key

  depends_on = [aws_organizations_aws_service_access.this]

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

module "aggregator_role" {
  source = "../../security/iam-role"
  count  = var.aggregator.enabled ? 1 : 0

  application              = var.application
  environment              = var.environment
  purpose                  = "config-aggregator"
  tags                     = var.tags
  permissions_boundary_arn = var.aggregator.permissions_boundary_arn
  managed_policy_arns      = ["arn:${local.partition}:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"]
  trust = {
    services   = ["config.amazonaws.com"]
    conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
  }
}

resource "aws_config_configuration_aggregator" "this" {
  count = var.aggregator.enabled ? 1 : 0

  region = var.aggregator.region
  name   = module.naming.names.aggregator

  organization_aggregation_source {
    all_regions = var.aggregator.all_regions
    regions     = var.aggregator.all_regions ? null : var.aggregator.regions
    role_arn    = module.aggregator_role[0].arn
  }

  tags = merge(module.naming.tags, { Name = module.naming.names.aggregator })

  depends_on = [
    module.aggregator_role,
    aws_organizations_delegated_administrator.this,
  ]
}

resource "aws_config_organization_managed_rule" "this" {
  for_each = local.organization_rule_instances

  region                      = each.value.region
  name                        = module.naming.names["rule-${each.value.key}"]
  rule_identifier             = each.value.rule_identifier
  description                 = each.value.description
  input_parameters            = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null
  maximum_execution_frequency = each.value.maximum_execution_frequency
  excluded_accounts           = length(each.value.excluded_accounts) > 0 ? each.value.excluded_accounts : null
  resource_types_scope        = each.value.resource_types_scope
  resource_id_scope           = each.value.resource_id_scope
  tag_key_scope               = each.value.tag_key_scope
  tag_value_scope             = each.value.tag_value_scope

  depends_on = [
    aws_config_configuration_recorder_status.this,
    aws_organizations_delegated_administrator.this,
  ]
}

resource "aws_config_organization_conformance_pack" "this" {
  for_each = local.conformance_pack_instances

  region                 = each.value.region
  name                   = module.naming.names["pack-${each.value.key}"]
  template_body          = each.value.template_body
  template_s3_uri        = each.value.template_s3_uri
  excluded_accounts      = length(each.value.excluded_accounts) > 0 ? each.value.excluded_accounts : null
  delivery_s3_bucket     = each.value.delivery_s3_bucket
  delivery_s3_key_prefix = each.value.delivery_s3_key_prefix

  dynamic "input_parameter" {
    for_each = each.value.input_parameters

    content {
      parameter_name  = input_parameter.key
      parameter_value = input_parameter.value
    }
  }

  depends_on = [
    aws_config_configuration_recorder_status.this,
    aws_organizations_delegated_administrator.this,
  ]
}
