module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    app = { max_length = 255 }
  }
}

resource "aws_amplify_app" "this" {
  name                   = local.name
  description            = coalesce(var.description, "${local.name} app")
  platform               = "WEB"
  custom_headers         = local.custom_headers
  enable_basic_auth      = var.basic_auth.enabled
  basic_auth_credentials = var.basic_auth.enabled ? base64encode("${var.basic_auth.username}:${var.basic_auth.password}") : null

  dynamic "custom_rule" {
    for_each = var.custom_rules

    content {
      source    = custom_rule.value.source
      target    = custom_rule.value.target
      status    = custom_rule.value.status
      condition = custom_rule.value.condition
    }
  }

  tags = merge(module.naming.tags, { Name = local.name })
}

resource "aws_amplify_branch" "this" {
  for_each = var.branches

  app_id            = aws_amplify_app.this.id
  branch_name       = each.key
  stage             = each.value.stage
  framework         = each.value.framework
  enable_auto_build = each.value.auto_build

  tags = merge(module.naming.tags, { Name = "${local.name}-${each.key}" })
}

resource "aws_amplify_domain_association" "this" {
  for_each = var.domain_associations

  app_id                 = aws_amplify_app.this.id
  domain_name            = each.key
  enable_auto_sub_domain = false
  wait_for_verification  = each.value.wait_for_verification

  certificate_settings {
    type                   = each.value.certificate_arn == null ? "AMPLIFY_MANAGED" : "CUSTOM"
    custom_certificate_arn = each.value.certificate_arn
  }

  dynamic "sub_domain" {
    for_each = each.value.sub_domains

    content {
      branch_name = aws_amplify_branch.this[sub_domain.value.branch_name].branch_name
      prefix      = sub_domain.value.prefix
    }
  }
}
