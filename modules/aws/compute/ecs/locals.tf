locals {
  arn_prefix          = "arn:${module.naming.partition}"
  region              = module.naming.region
  account_id          = module.naming.account_id
  dns_suffix          = module.naming.dns_suffix
  cluster_name        = module.naming.names.cluster
  kms_key_arn         = module.encryption.key_arn
  kms_encrypted       = var.kms.create || var.kms.key_id != null
  log_kms_key_arn     = try(coalesce(var.cloudwatch_logs.kms_key_arn, local.kms_key_arn), null)
  has_services        = length(var.services) > 0
  exec_enabled        = anytrue([for s in values(var.services) : s.execute_command])
  log_group_names     = { for k in keys(var.services) : k => "/ecs/${local.cluster_name}/${k}" }
  log_group_arns      = { for k, n in local.log_group_names : k => "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:${n}" }
  exec_log_group_name = "/aws/ecs/exec/${local.cluster_name}"
  exec_log_group_arn  = "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:${local.exec_log_group_name}"
  discovery_services  = { for k, s in var.services : k => s if s.service_discovery }
  connect_services    = { for k, s in var.services : k => s if s.service_connect.enabled }
  autoscaled_services = { for k, s in var.services : k => s if s.autoscaling.enabled }
  namespace_enabled   = length(local.discovery_services) + length(local.connect_services) > 0
  namespace_name      = coalesce(var.service_discovery_namespace, "${module.naming.name}.local")
  task_roles          = { for k, s in var.services : k => s if var.iam_role.create && s.task_role.create }
  task_role_arns      = { for k, s in var.services : k => contains(keys(local.task_roles), k) ? module.task_role[k].arn : coalesce(s.task_role.arn, var.iam_role.arn) }
  security_group_ids  = concat(var.security_group.create ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)
  service_ports       = distinct([for s in values(var.services) : s.container_port])
  internal_ports      = var.security_group.create ? toset([for k, s in var.services : tostring(s.container_port) if s.service_discovery || s.service_connect.enabled]) : toset([])

  names = merge(
    { cluster = { max_length = 255 } },
    { for k in keys(var.services) : "td-${k}" => { suffix = k, max_length = 255 } }
  )

  ingress_rules = merge(
    { for p in setproduct(range(length(var.security_group.ingress_security_group_ids)), local.service_ports) : "sg-${p[0]}-${p[1]}" => { description = "Port ${p[1]} from a security group", from_port = p[1], to_port = p[1], referenced_security_group_id = var.security_group.ingress_security_group_ids[p[0]] } },
    { for p in setproduct(range(length(var.security_group.ingress_cidr_blocks)), local.service_ports) : "cidr-${p[0]}-${p[1]}" => { description = "Port ${p[1]} from ${var.security_group.ingress_cidr_blocks[p[0]]}", from_port = p[1], to_port = p[1], cidr_ipv4 = var.security_group.ingress_cidr_blocks[p[0]] } },
    { for p in setproduct(range(length(var.security_group.ingress_prefix_list_ids)), local.service_ports) : "pl-${p[0]}-${p[1]}" => { description = "Port ${p[1]} from a prefix list", from_port = p[1], to_port = p[1], prefix_list_id = var.security_group.ingress_prefix_list_ids[p[0]] } },
    { for p in local.internal_ports : "self-${p}" => { description = "Port ${p} between the cluster services", from_port = tonumber(p), to_port = tonumber(p), self = true } }
  )

  egress_rules = merge(
    { for i, cidr in var.security_group.egress_cidr_blocks : "cidr-${i}" => { description = "Outbound to ${cidr}", ip_protocol = "-1", cidr_ipv4 = cidr } },
    { for i, pl in var.security_group.egress_prefix_list_ids : "pl-${i}" => { description = "Outbound to a prefix list", ip_protocol = "-1", prefix_list_id = pl } },
    { for i, sg in var.security_group.egress_security_group_ids : "sg-${i}" => { description = "Outbound to a security group", ip_protocol = "-1", referenced_security_group_id = sg } }
  )

  ecr_image_pattern = "^([0-9]{12})\\.dkr\\.ecr(?:-fips)?\\.([a-z0-9-]+)\\.amazonaws\\.com(?:\\.cn)?/([^:@]+)"
  ecr_repository_arns = distinct(flatten([
    for s in values(var.services) : [for m in regexall(local.ecr_image_pattern, s.image) : "${local.arn_prefix}:ecr:${m[1]}:${m[0]}:repository/${m[2]}"]
  ]))

  secret_refs         = distinct(flatten([for s in values(var.services) : values(s.secrets)]))
  secretsmanager_arns = distinct([for v in local.secret_refs : join(":", slice(split(":", v), 0, 7)) if can(regex("^arn:[^:]+:secretsmanager:", v))])
  ssm_parameter_arns  = distinct([for v in local.secret_refs : startswith(v, "arn:") ? v : "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter/${trimprefix(v, "/")}" if !can(regex("^arn:[^:]+:secretsmanager:", v))])
  secret_services = concat(
    length(local.secretsmanager_arns) > 0 ? ["secretsmanager.${local.region}.${local.dns_suffix}"] : [],
    length(local.ssm_parameter_arns) > 0 ? ["ssm.${local.region}.${local.dns_suffix}"] : []
  )

  fargate_key_context = [
    { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterAccount", values = [local.account_id] },
    { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterName", values = [local.cluster_name] }
  ]

  kms_service_statement_candidates = [
    {
      when = local.has_services
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${local.region}.${local.dns_suffix}"] }
        conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = concat(values(local.log_group_arns), local.exec_enabled ? [local.exec_log_group_arn] : []) }]
      }
    },
    {
      when = true
      statement = {
        sid        = "AllowFargateEphemeralStorage"
        actions    = ["kms:GenerateDataKeyWithoutPlaintext"]
        principals = { Service = ["fargate.${local.dns_suffix}"] }
        conditions = local.fargate_key_context
      }
    },
    {
      when = true
      statement = {
        sid        = "AllowFargateGrants"
        actions    = ["kms:CreateGrant"]
        principals = { Service = ["fargate.${local.dns_suffix}"] }
        conditions = concat(local.fargate_key_context, [{ test = "ForAllValues:StringEquals", variable = "kms:GrantOperations", values = ["Decrypt"] }])
      }
    }
  ]

  kms_service_statements = [for c in local.kms_service_statement_candidates : c.statement if c.when]

  execution_statement_candidates = [
    {
      when = true
      statement = {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for arn in values(local.log_group_arns) : "${arn}:*"]
      }
    },
    {
      when = true
      statement = {
        Sid      = "GetRegistryToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = ["*"]
      }
    },
    {
      when = length(local.ecr_repository_arns) > 0
      statement = {
        Sid      = "PullImages"
        Effect   = "Allow"
        Action   = ["ecr:BatchCheckLayerAvailability", "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage"]
        Resource = local.ecr_repository_arns
      }
    },
    {
      when = length(local.secretsmanager_arns) > 0
      statement = {
        Sid      = "ReadSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = local.secretsmanager_arns
      }
    },
    {
      when = length(local.ssm_parameter_arns) > 0
      statement = {
        Sid      = "ReadParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameters"]
        Resource = local.ssm_parameter_arns
      }
    },
    {
      when = length(local.secret_refs) > 0
      statement = {
        Sid       = "DecryptSecrets"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["*"]
        Condition = { StringEquals = { "kms:ViaService" = local.secret_services } }
      }
    }
  ]

  execution_statements = [for c in local.execution_statement_candidates : c.statement if c.when]

  task_statements = {
    for k, s in var.services : k => [for c in [
      {
        when = s.execute_command
        statement = {
          Sid      = "ExecChannels"
          Effect   = "Allow"
          Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
          Resource = ["*"]
        }
      },
      {
        when = s.execute_command
        statement = {
          Sid      = "ExecFindLogGroup"
          Effect   = "Allow"
          Action   = ["logs:DescribeLogGroups"]
          Resource = ["*"]
        }
      },
      {
        when = s.execute_command
        statement = {
          Sid      = "ExecWriteLogs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
          Resource = ["${local.exec_log_group_arn}:*"]
        }
      },
      {
        when = s.execute_command && local.kms_encrypted
        statement = {
          Sid      = "ExecDecryptSession"
          Effect   = "Allow"
          Action   = ["kms:Decrypt"]
          Resource = [local.kms_key_arn]
        }
      },
      {
        when = var.tracing.enabled
        statement = {
          Sid      = "WriteTraces"
          Effect   = "Allow"
          Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords", "xray:GetSamplingRules", "xray:GetSamplingTargets"]
          Resource = ["*"]
        }
      }
    ] : c.statement if c.when]
  }

  task_trust_conditions = [
    { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
    { test = "ArnLike", variable = "aws:SourceArn", values = ["${local.arn_prefix}:ecs:${local.region}:${local.account_id}:*"] }
  ]

  container_definitions = {
    for k, s in var.services : k => jsonencode([merge(
      {
        name                   = k
        image                  = s.image
        essential              = true
        readonlyRootFilesystem = coalesce(s.readonly_root_filesystem, var.readonly_root_filesystem)
        portMappings           = [{ name = k, containerPort = s.container_port, hostPort = s.container_port, protocol = "tcp" }]
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = module.log_group[k].name
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = "ecs"
          }
        }
      },
      length(s.command) > 0 ? { command = s.command } : {},
      length(s.environment) > 0 ? { environment = [for n, v in s.environment : { name = n, value = v }] } : {},
      length(s.secrets) > 0 ? { secrets = [for n, v in s.secrets : { name = n, valueFrom = v }] } : {},
      s.user == null ? {} : { user = s.user },
      length(s.writable_paths) > 0 ? { mountPoints = [for i, p in s.writable_paths : { sourceVolume = "scratch-${i}", containerPath = p, readOnly = false }] } : {}
    )])
  }
}
