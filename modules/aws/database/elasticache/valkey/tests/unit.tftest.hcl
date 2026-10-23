mock_provider "aws" {}

variables {
  application = "core"
  environment = "prod"
  name        = "cache"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_id  = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

# ------------------------------------------------------------------------------
# Naming
# ------------------------------------------------------------------------------

run "verify_rendered_names" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.replication_group_id == "core-prod-cache"
    error_message = "Replication group id must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.name == "core-prod-cache-sng"
    error_message = "Subnet group name must be the rendered name with a -sng suffix."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.name == "core-prod-cache-pg"
    error_message = "Parameter group name must be the rendered name with a -pg suffix."
  }

  assert {
    condition     = aws_security_group.this.name == "core-prod-cache-valkey-sg"
    error_message = "Security group name must be the rendered name with a -valkey-sg suffix."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.final_snapshot_identifier == "final-snapshot-core-prod-cache"
    error_message = "Final snapshot identifier must be derived from the rendered name."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.description == "Replication group for ElastiCache Valkey core cache"
    error_message = "Replication group description must include application and name."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.description == "Subnet group for ElastiCache Valkey core cache"
    error_message = "Subnet group description must include application and name."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.description == "Parameter group for ElastiCache Valkey core cache"
    error_message = "Parameter group description must include application and name."
  }

  assert {
    condition     = aws_security_group.this.description == "Security Group for ElastiCache Valkey core cache"
    error_message = "Security group description must include application and name."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_elasticache_replication_group.this.replication_group_id == "core-prod"
    error_message = "A null name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.name == "core-prod-sng" && aws_elasticache_parameter_group.this.name == "core-prod-pg" && aws_security_group.this.name == "core-prod-valkey-sg"
    error_message = "Sub-resource names must use the <application>-<environment> fallback."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.description == "Replication group for ElastiCache Valkey core"
    error_message = "Descriptions must fall back to the application name alone."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.tags["Name"] == "core-prod"
    error_message = "The Name tag must follow the <application>-<environment> fallback."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_elasticache_replication_group.this.replication_group_id == "core-prod"
    error_message = "An empty name must fall back to <application>-<environment>."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.name == "core-prod-sng" && aws_elasticache_parameter_group.this.name == "core-prod-pg" && aws_security_group.this.name == "core-prod-valkey-sg"
    error_message = "Sub-resource names must use the <application>-<environment> fallback."
  }
}

# ------------------------------------------------------------------------------
# Tags
# ------------------------------------------------------------------------------

run "verify_governance_tags" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.tags["Application"] == "core" && aws_elasticache_replication_group.this.tags["Environment"] == "prod" && aws_elasticache_replication_group.this.tags["Name"] == "core-prod-cache"
    error_message = "Replication group must carry Application, Environment and the rendered Name tag."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.tags["Application"] == "core" && aws_elasticache_subnet_group.this.tags["Environment"] == "prod" && aws_elasticache_subnet_group.this.tags["Name"] == "core-prod-cache-sng"
    error_message = "Subnet group must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.tags["Application"] == "core" && aws_elasticache_parameter_group.this.tags["Environment"] == "prod" && aws_elasticache_parameter_group.this.tags["Name"] == "core-prod-cache-pg"
    error_message = "Parameter group must carry governance tags with its own Name."
  }

  assert {
    condition     = aws_security_group.this.tags["Application"] == "core" && aws_security_group.this.tags["Environment"] == "prod" && aws_security_group.this.tags["Name"] == "core-prod-cache-valkey-sg"
    error_message = "Security group must carry governance tags with its own Name."
  }
}

run "verify_caller_tags_preserved" {
  command = plan

  variables {
    tags = {
      CacheTier  = "Session"
      CostCenter = "1234"
    }
  }

  assert {
    condition = alltrue([
      for t in [
        aws_elasticache_replication_group.this.tags,
        aws_elasticache_subnet_group.this.tags,
        aws_elasticache_parameter_group.this.tags,
        aws_security_group.this.tags,
      ] : t["CacheTier"] == "Session" && t["CostCenter"] == "1234"
    ])
    error_message = "Caller tags from var.tags must be preserved on every resource."
  }

  assert {
    condition = alltrue([
      for t in [
        aws_elasticache_replication_group.this.tags,
        aws_elasticache_subnet_group.this.tags,
        aws_elasticache_parameter_group.this.tags,
        aws_security_group.this.tags,
      ] : t["Application"] == "core" && t["Environment"] == "prod"
    ])
    error_message = "Governance tags must still be present alongside caller tags."
  }

  assert {
    condition     = aws_security_group.this.tags["Name"] == "core-prod-cache-valkey-sg"
    error_message = "Sub-resource Name override must survive caller tags."
  }
}

# ------------------------------------------------------------------------------
# Security defaults
# ------------------------------------------------------------------------------

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = tobool(aws_elasticache_replication_group.this.at_rest_encryption_enabled) == true
    error_message = "At-rest encryption must be enabled."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled == true
    error_message = "In-transit (TLS) encryption must be enabled."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.kms_key_id == var.kms_key_id
    error_message = "At-rest encryption must use the caller's KMS key."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.final_snapshot_identifier != null
    error_message = "A final snapshot must be taken on deletion."
  }

  assert {
    condition     = aws_elasticache_subnet_group.this.subnet_ids == toset(var.subnet_ids)
    error_message = "The subnet group must be placed only in the caller's subnets."
  }

  assert {
    condition     = aws_security_group.this.vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "The security group must be created in the caller's VPC."
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

run "verify_resource_wiring" {
  command = apply

  assert {
    condition     = aws_elasticache_replication_group.this.parameter_group_name == aws_elasticache_parameter_group.this.name
    error_message = "Replication group must use the module's parameter group."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.subnet_group_name == aws_elasticache_subnet_group.this.name
    error_message = "Replication group must use the module's subnet group."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.security_group_ids == toset([aws_security_group.this.id])
    error_message = "Replication group must use only the module's security group."
  }
}

# ------------------------------------------------------------------------------
# Parameters
# ------------------------------------------------------------------------------

run "verify_shipped_defaults" {
  command = plan

  assert {
    condition     = aws_elasticache_replication_group.this.engine == "valkey"
    error_message = "Engine must be valkey."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.engine_version == "9.0"
    error_message = "Default engine_version must be 9.0."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.node_type == "cache.t4g.micro"
    error_message = "Default node_type must be cache.t4g.micro."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 1
    error_message = "Default num_cache_clusters must be 1."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.port == 6379
    error_message = "Default port must be 6379."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.ip_discovery == "ipv4"
    error_message = "ip_discovery must be ipv4."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.maintenance_window == "sun:03:00-sun:06:00"
    error_message = "Maintenance window must be sun:03:00-sun:06:00."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.apply_immediately == true
    error_message = "apply_immediately must be true."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey9"
    error_message = "Default parameter group family must be valkey9."
  }

  assert {
    condition     = length(aws_elasticache_parameter_group.this.parameter) == 0
    error_message = "No custom parameters must be set by default."
  }

  assert {
    condition     = length(aws_security_group.this.egress) == 1 && one(aws_security_group.this.egress).cidr_blocks == tolist(["0.0.0.0/0"]) && one(aws_security_group.this.egress).protocol == "-1"
    error_message = "Default egress must allow all traffic to 0.0.0.0/0."
  }
}

run "verify_overrides" {
  command = plan

  variables {
    engine_version         = "8.0"
    node_type              = "cache.r7g.large"
    num_cache_clusters     = 3
    parameter_group_family = "valkey8"
    port                   = 6380
    allowed_cidr_blocks    = ["10.0.0.0/16", "10.1.0.0/16"]
    egress_cidr_blocks     = ["10.0.0.0/8"]

    parameters = [
      { name = "maxmemory-policy", value = "allkeys-lru" },
      { name = "timeout", value = "300" }
    ]
  }

  assert {
    condition     = aws_elasticache_replication_group.this.engine_version == "8.0"
    error_message = "engine_version override must pass through."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.node_type == "cache.r7g.large"
    error_message = "node_type override must pass through."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.num_cache_clusters == 3
    error_message = "num_cache_clusters override must pass through."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.port == 6380
    error_message = "port override must pass through to the replication group."
  }

  assert {
    condition     = aws_elasticache_parameter_group.this.family == "valkey8"
    error_message = "parameter_group_family override must pass through."
  }

  assert {
    condition = length(aws_elasticache_parameter_group.this.parameter) == 2 && alltrue([
      for want in ["maxmemory-policy=allkeys-lru", "timeout=300"] :
      contains([for p in aws_elasticache_parameter_group.this.parameter : "${p.name}=${p.value}"], want)
    ])
    error_message = "Custom parameters must be applied to the parameter group."
  }

  assert {
    condition     = length(aws_security_group.this.ingress) == 1
    error_message = "One ingress rule must be created when allowed_cidr_blocks is set."
  }

  assert {
    condition     = one(aws_security_group.this.ingress).from_port == 6380 && one(aws_security_group.this.ingress).to_port == 6380 && one(aws_security_group.this.ingress).protocol == "tcp"
    error_message = "Ingress must be limited to the Valkey port over TCP."
  }

  assert {
    condition     = one(aws_security_group.this.ingress).cidr_blocks == tolist(["10.0.0.0/16", "10.1.0.0/16"])
    error_message = "Ingress must be limited to allowed_cidr_blocks."
  }

  assert {
    condition     = one(aws_security_group.this.egress).cidr_blocks == tolist(["10.0.0.0/8"])
    error_message = "egress_cidr_blocks override must pass through."
  }

  assert {
    condition     = tobool(aws_elasticache_replication_group.this.at_rest_encryption_enabled) == true && aws_elasticache_replication_group.this.transit_encryption_enabled == true
    error_message = "Encryption must stay enabled when other inputs are overridden."
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
