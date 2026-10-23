mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"sts:AssumeRole\",\"Principal\":{\"Service\":\"rds.amazonaws.com\"}}]}"
    }
  }

  # The provider validates these computed values where other resources consume
  # them: role_arn must be an ARN, and target_group_name must start with a letter.
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/core-prod-pg-proxy-proxy-role"
    }
  }

  mock_resource "aws_db_proxy_default_target_group" {
    defaults = {
      name = "default"
    }
  }
}

variables {
  application            = "core"
  environment            = "prod"
  name                   = "pg-proxy"
  engine_family          = "POSTGRESQL"
  kms_key_arn            = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
  vpc_id                 = "vpc-0a1b2c3d4e5f67890"
  vpc_subnet_ids         = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  db_instance_identifier = "core-prod-db"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.name == "core-prod-pg-proxy"
    error_message = "Proxy name must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_iam_role.rds_proxy.name == "core-prod-pg-proxy-proxy-role"
    error_message = "Proxy role name must be the rendered name with a -proxy-role suffix."
  }

  assert {
    condition     = aws_security_group.this.name == "core-prod-pg-proxy-sg"
    error_message = "Proxy security group name must be the rendered name with a -sg suffix."
  }

  assert {
    condition     = aws_security_group.this.description == "Security Group for RDS Proxy core-prod-pg-proxy"
    error_message = "Proxy security group description must include the rendered name."
  }

  assert {
    condition     = aws_db_proxy_default_target_group.this.db_proxy_name == "core-prod-pg-proxy" && aws_db_proxy_target.this.db_proxy_name == "core-prod-pg-proxy"
    error_message = "Target group and target must attach to the module's proxy."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_db_proxy.this.name == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.rds_proxy.name == "core-prod-proxy-role" && aws_security_group.this.name == "core-prod-sg"
    error_message = "Sub-resource names must use the <application>-<environment> fallback."
  }

  assert {
    condition     = aws_db_proxy.this.tags["Name"] == "core-prod"
    error_message = "The Name tag must follow the <application>-<environment> fallback."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_db_proxy.this.name == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_iam_role.rds_proxy.name == "core-prod-proxy-role" && aws_security_group.this.name == "core-prod-sg"
    error_message = "Sub-resource names must use the <application>-<environment> fallback."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "verify_governance_tags" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.tags["Application"] == "core" && aws_db_proxy.this.tags["Environment"] == "prod" && aws_db_proxy.this.tags["Name"] == "core-prod-pg-proxy"
    error_message = "Proxy must carry Application, Environment and the rendered Name tag."
  }

  assert {
    condition     = aws_iam_role.rds_proxy.tags["Application"] == "core" && aws_iam_role.rds_proxy.tags["Environment"] == "prod" && aws_iam_role.rds_proxy.tags["Name"] == "core-prod-pg-proxy-proxy-role"
    error_message = "Proxy role must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_security_group.this.tags["Application"] == "core" && aws_security_group.this.tags["Environment"] == "prod" && aws_security_group.this.tags["Name"] == "core-prod-pg-proxy-sg"
    error_message = "Proxy security group must carry governance tags with its own Name."
  }
}

run "verify_caller_tags_preserved" {
  command = plan

  variables {
    tags = {
      Tier       = "ConnectionPooling"
      CostCenter = "1234"
    }
  }

  assert {
    condition = alltrue([
      for t in [
        aws_db_proxy.this.tags,
        aws_iam_role.rds_proxy.tags,
        aws_security_group.this.tags,
      ] : t["Tier"] == "ConnectionPooling" && t["CostCenter"] == "1234" && t["Application"] == "core" && t["Environment"] == "prod"
    ])
    error_message = "Caller tags must be preserved alongside governance tags on every taggable resource."
  }

  assert {
    condition     = aws_iam_role.rds_proxy.tags["Name"] == "core-prod-pg-proxy-proxy-role" && aws_security_group.this.tags["Name"] == "core-prod-pg-proxy-sg"
    error_message = "Sub-resource Name overrides must survive caller tags."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.require_tls == true
    error_message = "The proxy must require TLS."
  }

  assert {
    condition     = contains(flatten([for p in data.aws_iam_policy_document.rds_proxy_assume_role.statement[0].principals : p.identifiers]), "rds.amazonaws.com")
    error_message = "The proxy role must be assumable by rds.amazonaws.com."
  }

  assert {
    condition     = length(aws_iam_role_policy.rds_proxy_secrets) == 0
    error_message = "No secrets policy must be attached when there are no auth blocks."
  }

  assert {
    condition     = length(aws_security_group.this.egress) == 1 && one(aws_security_group.this.egress).cidr_blocks == tolist(["0.0.0.0/0"])
    error_message = "Proxy egress must allow outbound traffic."
  }

  assert {
    condition     = aws_security_group.this.vpc_id == var.vpc_id
    error_message = "The proxy security group must be created in the caller's VPC."
  }
}

run "verify_no_ingress_by_default" {
  # The ingress set is optional+computed, so its contents are only final after apply.
  command = apply

  assert {
    condition     = length(aws_security_group.this.ingress) == 0
    error_message = "No ingress rule must exist when allowed_cidr_blocks is empty."
  }
}

run "verify_auth_blocks_and_secrets_policy" {
  # The auth set carries a computed member, so it is only final after apply.
  command = apply

  variables {
    auth_blocks = [
      {
        description = "Application user"
        secret_arn  = "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-credentials-AbCdEf"
      }
    ]
  }

  assert {
    condition     = length(aws_db_proxy.this.auth) == 1
    error_message = "One auth block must be created per entry in auth_blocks."
  }

  assert {
    condition     = one(aws_db_proxy.this.auth).secret_arn == "arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-credentials-AbCdEf" && one(aws_db_proxy.this.auth).description == "Application user"
    error_message = "Auth block secret and description must pass through."
  }

  assert {
    condition     = one(aws_db_proxy.this.auth).auth_scheme == "SECRETS" && one(aws_db_proxy.this.auth).iam_auth == "DISABLED"
    error_message = "Auth blocks must default to SECRETS with IAM auth disabled."
  }

  assert {
    condition     = length(aws_iam_role_policy.rds_proxy_secrets) == 1
    error_message = "A secrets policy must be attached when auth blocks are set."
  }

  assert {
    condition     = aws_iam_role_policy.rds_proxy_secrets[0].name == "core-prod-pg-proxy-proxy-secrets-policy" && aws_iam_role_policy.rds_proxy_secrets[0].role == aws_iam_role.rds_proxy.id
    error_message = "The secrets policy must be named after the proxy and attached to the proxy role."
  }

  assert {
    condition     = data.aws_iam_policy_document.rds_proxy_secrets[0].statement[0].actions == toset(["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"])
    error_message = "The secrets statement must grant only GetSecretValue and DescribeSecret."
  }

  assert {
    condition     = data.aws_iam_policy_document.rds_proxy_secrets[0].statement[0].resources == toset(["arn:aws:secretsmanager:us-west-2:123456789012:secret:core-prod-db-credentials-AbCdEf"])
    error_message = "The secrets statement must be scoped to the auth block secrets."
  }

  assert {
    condition     = data.aws_iam_policy_document.rds_proxy_secrets[0].statement[1].actions == toset(["kms:Decrypt"]) && data.aws_iam_policy_document.rds_proxy_secrets[0].statement[1].resources == toset([var.kms_key_arn])
    error_message = "The KMS statement must grant only kms:Decrypt on kms_key_arn."
  }

  assert {
    condition     = aws_db_proxy.this.require_tls == true
    error_message = "TLS must stay required when auth blocks are set."
  }
}

# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------

run "verify_shipped_defaults" {
  command = plan

  assert {
    condition     = aws_db_proxy.this.engine_family == "POSTGRESQL"
    error_message = "engine_family must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.debug_logging == false
    error_message = "Debug logging must be off by default."
  }

  assert {
    condition     = aws_db_proxy.this.default_auth_scheme == "NONE"
    error_message = "Default auth scheme must be NONE."
  }

  assert {
    condition     = aws_db_proxy.this.endpoint_network_type == "IPV4" && aws_db_proxy.this.target_connection_network_type == "IPV4"
    error_message = "Endpoint and target network types must default to IPV4."
  }

  assert {
    condition     = aws_db_proxy.this.idle_client_timeout == 1800
    error_message = "Idle client timeout must default to 1800 seconds."
  }

  assert {
    condition     = aws_db_proxy.this.vpc_subnet_ids == toset(var.vpc_subnet_ids)
    error_message = "The proxy must use the caller's subnets."
  }

  assert {
    condition     = aws_db_proxy_target.this.db_instance_identifier == "core-prod-db"
    error_message = "The proxy target must register the caller's DB instance."
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.this) == 0 && length(aws_security_group.endpoint) == 0
    error_message = "No extra endpoints or endpoint security groups must be created by default."
  }
}

run "verify_resource_wiring" {
  command = apply

  assert {
    condition     = aws_db_proxy.this.role_arn == aws_iam_role.rds_proxy.arn
    error_message = "The proxy must use the module's IAM role."
  }

  assert {
    condition     = aws_db_proxy.this.vpc_security_group_ids == toset([aws_security_group.this.id])
    error_message = "The proxy must use only the module's security group."
  }

  assert {
    condition     = aws_db_proxy_target.this.target_group_name == aws_db_proxy_default_target_group.this.name
    error_message = "The target must register in the proxy's default target group."
  }

  assert {
    condition     = output.arn == aws_db_proxy.this.arn && output.endpoint == aws_db_proxy.this.endpoint
    error_message = "Outputs must expose the proxy ARN and default endpoint."
  }
}

run "verify_overrides" {
  command = plan

  variables {
    engine_family                  = "MYSQL"
    debug_logging                  = true
    default_auth_scheme            = "IAM_AUTH"
    endpoint_network_type          = "DUAL"
    target_connection_network_type = "IPV6"
    idle_client_timeout            = 900
    allowed_cidr_blocks            = ["10.0.0.0/16", "10.1.0.0/16"]

    connection_pool_config = {
      connection_borrow_timeout    = 120
      init_query                   = "SET timezone = 'UTC'"
      max_connections_percent      = 90
      max_idle_connections_percent = 50
      session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
    }
  }

  assert {
    condition     = aws_db_proxy.this.engine_family == "MYSQL"
    error_message = "engine_family override must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.debug_logging == true
    error_message = "debug_logging override must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.default_auth_scheme == "IAM_AUTH"
    error_message = "default_auth_scheme override must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.endpoint_network_type == "DUAL" && aws_db_proxy.this.target_connection_network_type == "IPV6"
    error_message = "Network type overrides must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.idle_client_timeout == 900
    error_message = "idle_client_timeout override must pass through."
  }

  assert {
    condition     = aws_db_proxy.this.require_tls == true
    error_message = "TLS must stay required when other inputs are overridden."
  }

  assert {
    condition     = length(aws_db_proxy_default_target_group.this.connection_pool_config) == 1
    error_message = "connection_pool_config must render one block when set."
  }

  assert {
    condition     = aws_db_proxy_default_target_group.this.connection_pool_config[0].connection_borrow_timeout == 120 && aws_db_proxy_default_target_group.this.connection_pool_config[0].max_connections_percent == 90 && aws_db_proxy_default_target_group.this.connection_pool_config[0].max_idle_connections_percent == 50
    error_message = "Connection pool sizing must pass through."
  }

  assert {
    condition     = aws_db_proxy_default_target_group.this.connection_pool_config[0].init_query == "SET timezone = 'UTC'" && aws_db_proxy_default_target_group.this.connection_pool_config[0].session_pinning_filters == toset(["EXCLUDE_VARIABLE_SETS"])
    error_message = "Connection pool init query and session pinning filters must pass through."
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 1
    error_message = "One ingress rule must be created when allowed_cidr_blocks is set."
  }

  assert {
    condition     = one(aws_security_group.this.ingress).cidr_blocks == tolist(["10.0.0.0/16", "10.1.0.0/16"]) && one(aws_security_group.this.ingress).protocol == "tcp"
    error_message = "Ingress must be limited to allowed_cidr_blocks over TCP."
  }
}

run "verify_endpoints" {
  command = apply

  variables {
    tags = {
      CostCenter = "1234"
    }

    endpoints = {
      reader = {
        vpc_subnet_ids      = ["subnet-0123456789abcdef0"]
        allowed_cidr_blocks = ["10.2.0.0/16"]
        target_role         = "READ_ONLY"
        tags = {
          Role = "reader"
        }
      }
      writer = {
        vpc_subnet_ids = ["subnet-0fedcba9876543210"]
      }
    }
  }

  assert {
    condition     = length(aws_db_proxy_endpoint.this) == 2 && length(aws_security_group.endpoint) == 2
    error_message = "One endpoint and one endpoint security group must be created per entry in endpoints."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].db_proxy_endpoint_name == "core-prod-pg-proxy-reader" && aws_db_proxy_endpoint.this["writer"].db_proxy_endpoint_name == "core-prod-pg-proxy-writer"
    error_message = "Endpoint names must be <rendered name>-<key>."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].db_proxy_name == aws_db_proxy.this.name
    error_message = "Endpoints must attach to the module's proxy."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].target_role == "READ_ONLY" && aws_db_proxy_endpoint.this["writer"].target_role == "READ_WRITE"
    error_message = "Endpoint target_role must pass through and default to READ_WRITE."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].vpc_subnet_ids == toset(["subnet-0123456789abcdef0"])
    error_message = "Endpoint subnets must pass through."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].vpc_security_group_ids == toset([aws_security_group.endpoint["reader"].id])
    error_message = "Each endpoint must use its own security group."
  }

  assert {
    condition     = aws_security_group.endpoint["reader"].name == "core-prod-pg-proxy-reader-sg" && aws_security_group.endpoint["writer"].name == "core-prod-pg-proxy-writer-sg"
    error_message = "Endpoint security group names must be <rendered name>-<key>-sg."
  }

  assert {
    condition     = length(aws_security_group.endpoint["reader"].ingress) == 1 && one(aws_security_group.endpoint["reader"].ingress).cidr_blocks == tolist(["10.2.0.0/16"]) && one(aws_security_group.endpoint["reader"].ingress).protocol == "tcp"
    error_message = "Endpoint ingress must be limited to the endpoint's allowed_cidr_blocks."
  }

  assert {
    condition     = length(aws_security_group.endpoint["writer"].ingress) == 0
    error_message = "An endpoint without allowed_cidr_blocks must have no ingress rule."
  }

  assert {
    condition     = aws_security_group.endpoint["reader"].tags["Name"] == "core-prod-pg-proxy-reader-sg" && aws_security_group.endpoint["reader"].tags["Role"] == "reader" && aws_security_group.endpoint["reader"].tags["CostCenter"] == "1234" && aws_security_group.endpoint["reader"].tags["Application"] == "core"
    error_message = "Endpoint security groups must carry governance, caller and endpoint tags with their own Name."
  }

  assert {
    condition     = aws_db_proxy_endpoint.this["reader"].tags["Role"] == "reader" && aws_db_proxy_endpoint.this["reader"].tags["CostCenter"] == "1234" && aws_db_proxy_endpoint.this["reader"].tags["Application"] == "core" && aws_db_proxy_endpoint.this["reader"].tags["Environment"] == "prod"
    error_message = "Endpoints must carry governance, caller and endpoint tags."
  }
}

# ------------------------------------------------------------------------------
# Validation
# ------------------------------------------------------------------------------

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}
