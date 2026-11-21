locals {
  arn_prefix     = "arn:${module.naming.partition}"
  region         = module.naming.region
  account_id     = module.naming.account_id
  dns_suffix     = module.naming.dns_suffix
  kms_key_arn    = module.encryption.key_arn
  has_jobs       = length(var.job_definitions) > 0
  logs_enabled   = var.cloudwatch_logs.enabled && local.has_jobs
  log_group_name = "/aws/batch/${module.naming.name}"
  log_group_arn  = "${local.arn_prefix}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"
  job_role_arn   = var.iam_role.create ? try(module.job_role[0].arn, null) : var.iam_role.arn
  efs_arn_prefix = "${local.arn_prefix}:elasticfilesystem:${local.region}:${local.account_id}"
  efs_mounts     = flatten([for k in keys(var.job_definitions) : values(var.job_definitions[k].efs_volumes)])

  ec2_environments   = { for k, c in var.compute_environments : k => c if contains(["EC2", "SPOT"], c.type) }
  has_ec2            = length(local.ec2_environments) > 0
  security_group_ids = concat(var.security_group.create && length(var.compute_environments) > 0 ? [module.security_group[0].id] : [], var.security_group.additional_security_group_ids)

  names = merge(
    { scheduling = { suffix = "fair-share", max_length = 128 } },
    { for k in keys(var.compute_environments) : "ce-${k}" => { suffix = k, max_length = 100 } },
    { for k in keys(var.job_queues) : "jq-${k}" => { suffix = k, max_length = 128 } },
    { for k in keys(var.job_definitions) : "jd-${k}" => { suffix = k, max_length = 128 } }
  )

  ecr_image_pattern = "^([0-9]{12})\\.dkr\\.ecr(?:-fips)?\\.([a-z0-9-]+)\\.amazonaws\\.com(?:\\.cn)?/([^:@]+)"
  ecr_repository_arns = distinct(flatten([
    for j in values(var.job_definitions) : [for m in regexall(local.ecr_image_pattern, j.image) : "${local.arn_prefix}:ecr:${m[1]}:${m[0]}:repository/${m[2]}"]
  ]))

  secret_refs         = distinct(flatten([for j in values(var.job_definitions) : values(j.secrets)]))
  secretsmanager_arns = distinct([for v in local.secret_refs : join(":", slice(split(":", v), 0, 7)) if can(regex("^arn:[^:]+:secretsmanager:", v))])
  ssm_parameter_arns  = distinct([for v in local.secret_refs : startswith(v, "arn:") ? v : "${local.arn_prefix}:ssm:${local.region}:${local.account_id}:parameter/${trimprefix(v, "/")}" if !can(regex("^arn:[^:]+:secretsmanager:", v))])
  secret_services = concat(
    length(local.secretsmanager_arns) > 0 ? ["secretsmanager.${local.region}.${local.dns_suffix}"] : [],
    length(local.ssm_parameter_arns) > 0 ? ["ssm.${local.region}.${local.dns_suffix}"] : []
  )

  kms_service_statement_candidates = [
    {
      when = local.logs_enabled
      statement = {
        sid        = "AllowCloudWatchLogs"
        actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        principals = { Service = ["logs.${local.region}.${local.dns_suffix}"] }
        conditions = [{ test = "ArnLike", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
      }
    },
    {
      when = local.has_ec2
      statement = {
        sid        = "AllowEbsThroughEc2"
        actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:CreateGrant", "kms:DescribeKey"]
        principals = { AWS = ["*"] }
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["ec2.${local.region}.${local.dns_suffix}"] }
        ]
      }
    }
  ]

  kms_service_statements = [for c in local.kms_service_statement_candidates : c.statement if c.when]

  execution_statement_candidates = [
    {
      when = local.logs_enabled
      statement = {
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${local.log_group_arn}:*"]
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

  job_statement_candidates = [
    for i, v in local.efs_mounts : {
      when = true
      statement = merge(
        {
          Sid      = "MountEfs${i}"
          Effect   = "Allow"
          Action   = v.read_only ? ["elasticfilesystem:ClientMount"] : ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
          Resource = ["${local.efs_arn_prefix}:file-system/${v.file_system_id}"]
        },
        v.access_point_id == null ? {} : { Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = "${local.efs_arn_prefix}:access-point/${v.access_point_id}" } } }
      )
    }
  ]

  job_statements = [for c in local.job_statement_candidates : c.statement if c.when]

  task_trust_conditions = [
    { test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] },
    { test = "ArnLike", variable = "aws:SourceArn", values = ["${local.arn_prefix}:ecs:${local.region}:${local.account_id}:*"] }
  ]

  egress_rules = merge(
    { for i, cidr in var.security_group.egress_cidr_blocks : "https-${i}" => { description = "HTTPS to ${cidr}", ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = strcontains(cidr, ":") ? null : cidr, cidr_ipv6 = strcontains(cidr, ":") ? cidr : null } },
    { for i, pl in var.security_group.egress_prefix_list_ids : "pl-${i}" => { description = "Outbound to a prefix list", ip_protocol = "-1", prefix_list_id = pl } },
    { for i, sg in var.security_group.egress_security_group_ids : "sg-${i}" => { description = "Outbound to a security group", ip_protocol = "-1", referenced_security_group_id = sg } },
    length(local.efs_mounts) > 0 ? { nfs = { description = "NFS to EFS mount targets in the VPC", ip_protocol = "tcp", from_port = 2049, to_port = 2049, cidr_ipv4 = one(data.aws_vpc.this[*].cidr_block) } } : {}
  )

  container_properties = {
    for k, j in var.job_definitions : k => jsonencode(merge(
      {
        image                  = j.image
        jobRoleArn             = local.job_role_arn
        executionRoleArn       = module.execution_role[0].arn
        readonlyRootFilesystem = coalesce(j.readonly_root_filesystem, var.readonly_root_filesystem)
        resourceRequirements = [
          { type = "VCPU", value = tostring(j.vcpu) },
          { type = "MEMORY", value = tostring(j.memory) }
        ]
      },
      length(j.command) > 0 ? { command = j.command } : {},
      length(j.environment) > 0 ? { environment = [for n, v in j.environment : { name = n, value = v }] } : {},
      length(j.secrets) > 0 ? { secrets = [for n, v in j.secrets : { name = n, valueFrom = v }] } : {},
      j.user == null ? {} : { user = j.user },
      length(j.writable_paths) + length(j.efs_volumes) > 0 ? {
        volumes = concat(
          [for i, p in j.writable_paths : { name = "scratch-${i}" }],
          [for n, v in j.efs_volumes : {
            name = n
            efsVolumeConfiguration = merge(
              {
                fileSystemId        = v.file_system_id
                transitEncryption   = "ENABLED"
                authorizationConfig = merge({ iam = v.access_point_id != null ? "ENABLED" : "DISABLED" }, v.access_point_id == null ? {} : { accessPointId = v.access_point_id })
              },
              v.root_directory == null ? {} : { rootDirectory = v.root_directory }
            )
          }]
        )
      } : {},
      length(j.writable_paths) + length(j.efs_volumes) > 0 ? {
        mountPoints = concat(
          [for i, p in j.writable_paths : { sourceVolume = "scratch-${i}", containerPath = p, readOnly = false }],
          [for n, v in j.efs_volumes : { sourceVolume = n, containerPath = v.container_path, readOnly = v.read_only }]
        )
      } : {},
      j.platform == "FARGATE" ? { networkConfiguration = { assignPublicIp = "DISABLED" } } : {},
      j.platform == "FARGATE" ? { fargatePlatformConfiguration = { platformVersion = "LATEST" } } : {},
      j.platform == "EC2" ? { privileged = false } : {},
      local.logs_enabled ? {
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = module.log_group[0].name
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = k
          }
        }
      } : {}
    ))
  }
}
