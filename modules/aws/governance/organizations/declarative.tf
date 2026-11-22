locals {
  dp = var.declarative_policies

  ec2_image_criteria = { for i, c in local.dp.ec2.allowed_images_settings.criteria : "criteria_${i + 1}" => merge(
    { for k, v in { allowed_image_providers = { "@@assign" = c.allowed_image_providers } } : k => v if c.allowed_image_providers != null },
    { for k, v in { image_names = { "@@assign" = c.image_names } } : k => v if c.image_names != null },
    { for k, v in { marketplace_product_codes = { "@@assign" = c.marketplace_product_codes } } : k => v if c.marketplace_product_codes != null },
    { for k, v in { creation_date_condition = { maximum_days_since_created = { "@@assign" = c.maximum_days_since_created } } } : k => v if c.maximum_days_since_created != null },
    { for k, v in { deprecation_time_condition = { maximum_days_since_deprecated = { "@@assign" = c.maximum_days_since_deprecated } } } : k => v if c.maximum_days_since_deprecated != null },
  ) }

  ec2_attributes = merge(
    {
      instance_metadata_defaults = {
        http_tokens                 = { "@@assign" = "required" }
        http_put_response_hop_limit = { "@@assign" = tostring(local.dp.ec2.http_put_response_hop_limit) }
        http_tokens_enforced        = { "@@assign" = local.dp.ec2.http_tokens_enforced }
      }
      snapshot_block_public_access = { state = { "@@assign" = local.dp.ec2.snapshot_block_public_access } }
      image_block_public_access    = { state = { "@@assign" = local.dp.ec2.image_block_public_access } }
      serial_console_access        = { status = { "@@assign" = local.dp.ec2.serial_console_access } }
    },
    { for k, v in {
      vpc_block_public_access = {
        internet_gateway_block = {
          mode               = { "@@assign" = local.dp.ec2.vpc_block_public_access.mode }
          exclusions_allowed = { "@@assign" = local.dp.ec2.vpc_block_public_access.exclusions_allowed }
        }
      }
    } : k => v if local.dp.ec2.vpc_block_public_access.enabled },
    { for k, v in {
      allowed_images_settings = merge(
        { state = { "@@assign" = local.dp.ec2.allowed_images_settings.state } },
        { for ck, cv in { image_criteria = local.ec2_image_criteria } : ck => cv if length(local.ec2_image_criteria) > 0 },
      )
    } : k => v if local.dp.ec2.allowed_images_settings.enabled },
    { for k, v in { exception_message = { "@@assign" = local.dp.ec2.exception_message } } : k => v if local.dp.ec2.exception_message != null },
  )

  tag_policy_tags = { for k, v in local.dp.tag_policy.tag_keys : k => merge(
    { tag_key = { "@@assign" = k, "@@operators_allowed_for_child_policies" = ["@@none"] } },
    { for tk, tv in { tag_value = { "@@assign" = try(tolist(v.allowed_values), []) } } : tk => tv if v.allowed_values != null },
    { for tk, tv in { enforced_for = { "@@assign" = local.dp.tag_policy.enforced_for } } : tk => tv if length(local.dp.tag_policy.enforced_for) > 0 },
  ) }

  declarative_documents = {
    ec2        = jsonencode({ ec2_attributes = local.ec2_attributes })
    s3         = jsonencode({ s3_attributes = { public_access_block_configuration = { "@@assign" = "all" } } })
    tag_policy = jsonencode({ tags = local.tag_policy_tags })
    ai_services_opt_out = jsonencode({ services = merge(
      { default = { opt_out_policy = { "@@assign" = local.dp.ai_services_opt_out.default_policy } } },
      { for s, v in local.dp.ai_services_opt_out.service_overrides : s => { opt_out_policy = { "@@assign" = v } } },
    ) })
  }

  declarative_types = {
    ec2                 = "DECLARATIVE_POLICY_EC2"
    s3                  = "S3_POLICY"
    tag_policy          = "TAG_POLICY"
    ai_services_opt_out = "AISERVICES_OPT_OUT_POLICY"
  }

  declarative_descriptions = {
    ec2                 = "EC2 baseline: IMDSv2 defaults, snapshot and AMI block public access, serial console off."
    s3                  = "Enforces all four S3 Block Public Access settings at account level."
    tag_policy          = "Standardises governance tag keys and allowed values."
    ai_services_opt_out = "Controls content use by AWS AI services."
  }

  declarative_library = { for k, p in local.dp : k => {
    type        = local.declarative_types[k]
    targets     = p.targets
    description = local.declarative_descriptions[k]
    content     = local.declarative_documents[k]
  } }
}
