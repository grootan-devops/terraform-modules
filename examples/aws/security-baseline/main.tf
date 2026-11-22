data "aws_caller_identity" "current" {}

data "aws_iam_session_context" "deployer" {
  arn = data.aws_caller_identity.current.arn
}

module "organization" {
  source = "../../../modules/aws/governance/organizations"

  environment = var.environment
  service_control_policies = {
    deny_leave_organization = { targets = ["root"] }
    protect_audit_buckets   = { targets = ["ou-abcd-11111111"], bucket_arns = [module.trail.bucket_arn] }
  }
  custom_policies = {
    protect-backups = {
      type        = "SERVICE_CONTROL_POLICY"
      description = "Only the deployer role changes backup vaults, plans and recovery points"
      content     = module.backup_guardrail.json
      targets     = ["ou-abcd-11111111"]
    }
  }
}

module "backup_guardrail" {
  source = "../../../modules/aws/core/policy-document"

  statements = [{
    sid    = "ProtectBackups"
    effect = "Deny"
    actions = [
      "backup:DeleteBackupPlan",
      "backup:DeleteBackupSelection",
      "backup:DeleteBackupVault",
      "backup:DeleteBackupVaultAccessPolicy",
      "backup:DeleteBackupVaultLockConfiguration",
      "backup:DeleteBackupVaultNotifications",
      "backup:DeleteRecoveryPoint",
      "backup:PutBackupVaultAccessPolicy",
      "backup:PutBackupVaultLockConfiguration",
      "backup:UpdateBackupPlan",
      "backup:UpdateRecoveryPointLifecycle"
    ]
    resources  = ["*"]
    conditions = [{ test = "ArnNotLike", variable = "aws:PrincipalArn", values = [replace(data.aws_iam_session_context.deployer.issuer_arn, data.aws_caller_identity.current.account_id, "*")] }]
  }]
}

module "identity_center" {
  source = "../../../modules/aws/security/identity-center"

  environment = var.environment
  permission_sets = {
    admin = { managed_policy_arns = ["arn:aws:iam::aws:policy/AdministratorAccess"] }
    audit = {
      managed_policy_arns = ["arn:aws:iam::aws:policy/SecurityAudit"]
      policy_statements   = [{ sid = "DenySecretValues", effect = "Deny", actions = ["secretsmanager:GetSecretValue"], resources = ["*"] }]
    }
  }
  groups = {
    platform-admins = { description = "Platform administrators" }
    auditors        = { description = "Security auditors" }
  }
  account_assignments = {
    admins   = { permission_set = "admin", group = "platform-admins", account_ids = var.workload_account_ids }
    auditors = { permission_set = "audit", group = "auditors", account_ids = var.workload_account_ids }
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

  environment                = var.environment
  regions                    = var.regions
  organization_configuration = { enabled = false }
}

module "guardduty" {
  source = "../../../modules/aws/security/guardduty"

  environment                = var.environment
  regions                    = var.regions
  organization_configuration = { enabled = false }
}

module "detective" {
  source = "../../../modules/aws/security/detective"

  environment                = var.environment
  regions                    = var.regions
  behavior_graph             = { enabled = true }
  organization_configuration = { enabled = false }

  depends_on = [module.guardduty]
}

module "inspector" {
  source = "../../../modules/aws/security/inspector"

  environment                = var.environment
  regions                    = var.regions
  organization_configuration = { enabled = false }
}

module "access_analyzer" {
  source = "../../../modules/aws/security/iam-access-analyzer"

  environment                = var.environment
  regions                    = var.regions
  organization_configuration = { enabled = false }
  unused_access              = { unused_access_age = 45 }
}

module "systems_manager" {
  source = "../../../modules/aws/governance/systems-manager"

  environment = var.environment
  regions     = var.regions
  kms         = { create = true }
}

module "backup" {
  source = "../../../modules/aws/storage/backup"

  environment           = var.environment
  regions               = var.regions
  vault_admin_role_arns = [data.aws_iam_session_context.deployer.issuer_arn]
  vault_notifications = {
    enabled        = true
    sns_topic_arns = { for region in var.regions : region => module.routing.topic_arns[region]["warning"] }
  }
}

module "routing" {
  source = "../../../modules/aws/observability/alarm-routing"

  environment                             = var.environment
  regions                                 = var.regions
  email_subscriptions                     = { critical = ["security@example.com"] }
  additional_publisher_service_principals = ["backup.amazonaws.com", "budgets.amazonaws.com", "costalerts.amazonaws.com"]
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
