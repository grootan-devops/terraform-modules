module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  tags        = var.tags
}

resource "aws_detective_organization_admin_account" "this" {
  for_each = local.admin_regions

  region     = each.key
  account_id = var.organization_admin.account_id

  lifecycle {
    precondition {
      condition     = var.organization_admin.account_id != local.account_id
      error_message = "organization_admin.account_id: a member account."
    }
  }
}

resource "aws_detective_graph" "this" {
  for_each = local.graph_regions

  region = each.key

  tags = module.naming.tags
}

resource "aws_detective_organization_configuration" "this" {
  for_each = local.graph_regions

  region      = each.key
  graph_arn   = aws_detective_graph.this[each.key].graph_arn
  auto_enable = var.behavior_graph.auto_enable
}

resource "aws_detective_member" "this" {
  for_each = local.members

  region        = each.value.region
  graph_arn     = aws_detective_graph.this[each.value.region].graph_arn
  account_id    = each.value.account_id
  email_address = each.value.email_address

  lifecycle {
    precondition {
      condition     = each.value.account_id != local.account_id
      error_message = "behavior_graph.member_accounts: not the administrator account."
    }
  }
}
