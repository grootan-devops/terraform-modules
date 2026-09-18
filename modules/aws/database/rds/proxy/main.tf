resource "aws_db_proxy" "this" {
  name           = local.rendered_name
  engine_family  = var.engine_family
  role_arn       = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids = var.vpc_subnet_ids

  debug_logging                  = var.debug_logging
  default_auth_scheme            = var.default_auth_scheme
  endpoint_network_type          = var.endpoint_network_type
  idle_client_timeout            = var.idle_client_timeout
  require_tls                    = true
  target_connection_network_type = var.target_connection_network_type
  vpc_security_group_ids         = [aws_security_group.this.id]

  dynamic "auth" {
    for_each = var.auth_blocks
    content {
      auth_scheme               = auth.value.auth_scheme
      client_password_auth_type = auth.value.client_password_auth_type
      description               = auth.value.description
      iam_auth                  = auth.value.iam_auth
      secret_arn                = auth.value.secret_arn
      username                  = auth.value.username
    }
  }

  tags = local.tags
}

resource "aws_db_proxy_default_target_group" "this" {
  db_proxy_name = aws_db_proxy.this.name

  dynamic "connection_pool_config" {
    for_each = length(keys(var.connection_pool_config)) > 0 ? [var.connection_pool_config] : []
    content {
      connection_borrow_timeout    = connection_pool_config.value.connection_borrow_timeout
      init_query                   = connection_pool_config.value.init_query
      max_connections_percent      = connection_pool_config.value.max_connections_percent
      max_idle_connections_percent = connection_pool_config.value.max_idle_connections_percent
      session_pinning_filters      = connection_pool_config.value.session_pinning_filters
    }
  }
}

resource "aws_db_proxy_target" "this" {
  db_proxy_name          = aws_db_proxy.this.name
  target_group_name      = aws_db_proxy_default_target_group.this.name
  db_instance_identifier = var.db_instance_identifier
}

resource "aws_db_proxy_endpoint" "this" {
  for_each = var.endpoints

  db_proxy_name          = aws_db_proxy.this.name
  db_proxy_endpoint_name = "${local.rendered_name}-${each.key}"
  vpc_subnet_ids         = each.value.vpc_subnet_ids
  vpc_security_group_ids = [aws_security_group.endpoint[each.key].id]
  target_role            = each.value.target_role

  tags = merge(local.tags, each.value.tags)
}
