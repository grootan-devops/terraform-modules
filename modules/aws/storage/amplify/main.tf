resource "aws_amplify_app" "this" {
  name = local.rendered_name

  platform = "WEB"

  enable_basic_auth      = var.basic_auth.enable
  basic_auth_credentials = var.basic_auth.enable ? base64encode("${var.basic_auth.username}:${var.basic_auth.password}") : null

  custom_headers = var.custom_headers

  dynamic "custom_rule" {
    for_each = var.custom_rules
    content {
      source    = custom_rule.value.source
      target    = custom_rule.value.target
      status    = custom_rule.value.status
      condition = custom_rule.value.condition
    }
  }

  tags = local.tags
}

resource "aws_amplify_branch" "this" {
  for_each = toset(var.branches)

  app_id      = aws_amplify_app.this.id
  branch_name = each.key

  enable_auto_build = false

  tags = merge(local.tags, { Name = each.key })
}

resource "aws_amplify_domain_association" "this" {
  for_each               = var.domain_associations
  app_id                 = aws_amplify_app.this.id
  domain_name            = each.key
  enable_auto_sub_domain = false
  wait_for_verification  = true

  certificate_settings {
    type                   = each.value.acm_certificate_arn != null ? "CUSTOM" : "AMPLIFY_MANAGED"
    custom_certificate_arn = each.value.acm_certificate_arn
  }

  dynamic "sub_domain" {
    for_each = each.value.sub_domains
    content {
      branch_name = aws_amplify_branch.this[sub_domain.value.branch_name].branch_name
      prefix      = sub_domain.value.prefix
    }
  }
}
