module "organization" {
  source = "../../../modules/aws/governance/organizations"

  environment = var.environment
  service_control_policies = {
    deny_leave_organization = { targets = ["root"] }
    protect_audit_buckets   = { targets = ["ou-abcd-11111111"], bucket_arns = [module.trail.bucket_arn] }
  }
}

module "baseline" {
  source = "../../../modules/aws/governance/account-baseline"

  environment = var.environment
  regions     = var.regions
  alternate_contacts = {
    security = { name = "Security Team", title = "Security", email_address = "security@example.com", phone_number = "+10000000000" }
  }
}

module "trail" {
  source = "../../../modules/aws/security/cloudtrail"

  environment = var.environment
  trail       = { is_organization_trail = false }
}

module "config" {
  source = "../../../modules/aws/security/config"

  environment = var.environment
  regions     = var.regions
}

module "security_hub" {
  source = "../../../modules/aws/security/security-hub"

  environment = var.environment
}

module "guardduty" {
  source = "../../../modules/aws/security/guardduty"

  environment = var.environment
  regions     = var.regions
}

module "routing" {
  source = "../../../modules/aws/observability/alarm-routing"

  environment                             = var.environment
  regions                                 = [var.region]
  email_subscriptions                     = { critical = ["security@example.com"] }
  additional_publisher_service_principals = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
}

module "costs" {
  source = "../../../modules/aws/governance/cost-guardrails"

  environment   = var.environment
  notifications = { sns = { enabled = true, topic_arn = module.routing.topic_arns[var.region]["warning"] } }
  budgets = {
    account = { amount = 1000 }
  }
}

module "alarms" {
  source = "../../../modules/aws/observability/cloudwatch-alarms"

  application                   = "platform"
  environment                   = var.environment
  name                          = "security"
  notifications                 = { enabled = true, topic_arns = module.routing.topic_arns }
  cis_cloudtrail_metric_filters = { enabled = true, log_group_name = module.trail.log_group_name }
}
