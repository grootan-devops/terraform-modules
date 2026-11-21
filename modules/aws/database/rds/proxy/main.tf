module "naming" {
  source = "../../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = merge(
    { proxy = { max_length = 63 } },
    { for k in keys(var.endpoints) : "endpoint-${k}" => { suffix = k, max_length = 63 } }
  )
}

module "role" {
  source = "../../../security/iam-role"
  count  = var.iam_role.create ? 1 : 0

  application              = var.application
  environment              = var.environment
  name                     = var.name
  purpose                  = "proxy"
  tags                     = var.tags
  role_name                = var.iam_role.name
  path                     = var.iam_role.path
  permissions_boundary_arn = var.iam_role.permissions_boundary_arn
  managed_policy_arns      = var.iam_role.managed_policy_arns
  policy_statements        = var.iam_role.policy_statements
  policy_documents         = length(local.role_statements) > 0 ? [jsonencode({ Version = "2012-10-17", Statement = local.role_statements })] : []
  trust = {
    services = ["rds.${module.naming.dns_suffix}"]
  }
}

#trivy:ignore:AVD-AWS-0104
module "security_group" {
  source = "../../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "proxy"
  tags          = var.tags
  vpc_id        = var.vpc_id
  description   = "${module.naming.name} RDS Proxy"
  ingress_rules = local.ingress_rules
  egress_rules  = local.egress_rules
}

module "log_group" {
  source = "../../../observability/log-group"
  count  = var.cloudwatch_logs.enabled ? 1 : 0

  application                 = var.application
  environment                 = var.environment
  name                        = var.name
  tags                        = var.tags
  log_group_name              = local.log_group_name
  retention_in_days           = var.cloudwatch_logs.retention_in_days
  log_group_class             = var.cloudwatch_logs.log_group_class
  deletion_protection_enabled = var.cloudwatch_logs.deletion_protection_enabled
  kms_key_arn                 = var.cloudwatch_logs.kms_key_arn
}

resource "aws_db_proxy" "this" {
  name                           = local.proxy_name
  engine_family                  = var.engine_family
  role_arn                       = local.role_arn
  vpc_subnet_ids                 = var.subnet_ids
  vpc_security_group_ids         = local.security_group_ids
  require_tls                    = true
  default_auth_scheme            = var.default_auth_scheme
  idle_client_timeout            = var.idle_client_timeout
  debug_logging                  = var.debug_logging
  endpoint_network_type          = "IPV4"
  target_connection_network_type = "IPV4"

  dynamic "auth" {
    for_each = var.auth
    content {
      auth_scheme               = auth.value.auth_scheme
      secret_arn                = auth.value.secret_arn
      iam_auth                  = auth.value.iam_auth
      client_password_auth_type = auth.value.client_password_auth_type
      description               = auth.value.description
      username                  = auth.value.username
    }
  }

  tags = merge(module.naming.tags, { Name = local.proxy_name })

  depends_on = [module.log_group, module.role]
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  connection_pool_config {
    connection_borrow_timeout    = var.connection_pool.connection_borrow_timeout
    max_connections_percent      = var.connection_pool.max_connections_percent
    max_idle_connections_percent = var.connection_pool.max_idle_connections_percent
    init_query                   = var.connection_pool.init_query
    session_pinning_filters      = var.connection_pool.session_pinning_filters
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = var.target.db_instance_identifier
}

resource "aws_db_proxy_endpoint" "this" {
  for_each = var.endpoints

  db_proxy_name          = aws_db_proxy.this.name
  db_proxy_endpoint_name = module.naming.names["endpoint-${each.key}"]
  vpc_subnet_ids         = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids
  vpc_security_group_ids = length(each.value.security_group_ids) > 0 ? each.value.security_group_ids : local.security_group_ids
  target_role            = "READ_WRITE"

  tags = merge(module.naming.tags, { Name = module.naming.names["endpoint-${each.key}"] })
}
