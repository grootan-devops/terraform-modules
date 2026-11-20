module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
  names = merge(
    {
      aggregator = { max_length = 256 }
      bucket     = { suffix = "config", uniqueness = "global", max_length = 63 }
    },
    local.rule_names,
  )
}

module "encryption" {
  source = "../../core/encryption"

  application        = var.application
  environment        = var.environment
  purpose            = "config"
  tags               = var.tags
  kms                = var.kms
  service_statements = local.kms_service_statements
}

module "kms_policy" {
  source = "../../core/policy-document"

  statements        = local.kms_service_statements
  default_resources = ["*"]
}

resource "aws_iam_service_linked_role" "config" {
  count = var.service_linked_role.enabled ? 1 : 0

  aws_service_name = "config.amazonaws.com"
  description      = "AWS Config recorder role"

  tags = merge(module.naming.tags, { Name = "AWSServiceRoleForConfig" })
}

resource "aws_config_configuration_recorder" "this" {
  for_each = local.recorder_regions

  region   = each.key
  name     = var.recorder.name
  role_arn = local.service_linked_role_arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = each.key == local.global_resource_region

    recording_strategy {
      use_only = "ALL_SUPPORTED_RESOURCE_TYPES"
    }
  }

  recording_mode {
    recording_frequency = var.recorder.recording_frequency

    dynamic "recording_mode_override" {
      for_each = var.recorder.recording_mode_override.enabled ? [var.recorder.recording_mode_override] : []

      content {
        description         = recording_mode_override.value.description
        recording_frequency = recording_mode_override.value.recording_frequency
        resource_types      = recording_mode_override.value.resource_types
      }
    }
  }

  depends_on = [aws_iam_service_linked_role.config]

  lifecycle {
    precondition {
      condition     = contains(local.regions, local.global_resource_region)
      error_message = "recorder.global_resource_region: one of regions."
    }
  }
}

resource "aws_config_delivery_channel" "this" {
  for_each = local.recorder_regions

  region         = each.key
  name           = var.recorder.delivery_channel_name
  s3_bucket_name = local.bucket_name
  s3_key_prefix  = local.bucket_key_prefix == "" ? null : local.bucket_key_prefix
  s3_kms_key_arn = local.kms_key_arn

  snapshot_delivery_properties {
    delivery_frequency = var.recorder.snapshot_delivery_frequency
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    module.bucket,
  ]
}

resource "aws_config_configuration_recorder_status" "this" {
  for_each = local.recorder_regions

  region     = each.key
  name       = aws_config_configuration_recorder.this[each.key].name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

resource "aws_config_retention_configuration" "this" {
  for_each = local.recorder_regions

  region                   = each.key
  retention_period_in_days = var.recorder.retention_period_in_days
}

resource "aws_config_config_rule" "this" {
  for_each = local.account_rule_instances

  region                      = each.value.region
  name                        = module.naming.names["rule-${each.value.key}"]
  description                 = each.value.description
  input_parameters            = length(each.value.input_parameters) > 0 ? jsonencode(each.value.input_parameters) : null
  maximum_execution_frequency = each.value.maximum_execution_frequency

  source {
    owner             = "AWS"
    source_identifier = each.value.rule_identifier
  }

  dynamic "scope" {
    for_each = each.value.resource_types_scope != null || each.value.resource_id_scope != null || each.value.tag_key_scope != null ? [true] : []

    content {
      compliance_resource_types = each.value.resource_types_scope
      compliance_resource_id    = each.value.resource_id_scope
      tag_key                   = each.value.tag_key_scope
      tag_value                 = each.value.tag_value_scope
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["rule-${each.value.key}"] })

  depends_on = [aws_config_configuration_recorder_status.this]
}

resource "aws_config_remediation_configuration" "this" {
  for_each = var.remediations

  region                     = each.value.region
  config_rule_name           = each.value.config_rule_name
  target_type                = each.value.target_type
  target_id                  = each.value.target_id
  target_version             = each.value.target_version
  resource_type              = each.value.resource_type
  automatic                  = each.value.automatic
  maximum_automatic_attempts = each.value.maximum_automatic_attempts
  retry_attempt_seconds      = each.value.retry_attempt_seconds

  dynamic "parameter" {
    for_each = each.value.parameters

    content {
      name           = parameter.key
      static_value   = parameter.value.static_value
      static_values  = parameter.value.static_values
      resource_value = parameter.value.resource_value
    }
  }

  dynamic "execution_controls" {
    for_each = each.value.execution_controls == null ? [] : [each.value.execution_controls]

    content {
      ssm_controls {
        concurrent_execution_rate_percentage = execution_controls.value.concurrent_execution_rate_percentage
        error_percentage                     = execution_controls.value.error_percentage
      }
    }
  }

  depends_on = [
    aws_config_configuration_recorder_status.this,
    aws_config_config_rule.this,
  ]

  lifecycle {
    precondition {
      condition     = !each.value.automatic || var.allow_automatic_remediation
      error_message = "remediations: automatic needs allow_automatic_remediation."
    }
  }
}
