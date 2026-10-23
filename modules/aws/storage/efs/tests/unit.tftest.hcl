mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "shared"
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  kms_key_arn = "arn:aws:kms:us-west-2:123456789012:key/12345678-1234-1234-1234-123456789012"
}

run "verify_naming" {
  command = plan

  variables {
    access_points = {
      app = {}
    }
  }

  assert {
    condition     = aws_efs_file_system.this.creation_token == "core-prod-shared"
    error_message = "File system creation token must render as <application>-<environment>-<name>."
  }

  assert {
    condition     = aws_security_group.this[0].name == "core-prod-shared-efs-sg"
    error_message = "Security group name must render as <rendered_name>-efs-sg."
  }

  assert {
    condition     = aws_security_group.this[0].description == "Security group for EFS mount targets in core-prod-shared"
    error_message = "Security group description must reference the rendered name."
  }

  assert {
    condition     = aws_efs_access_point.this["app"].tags["Name"] == "core-prod-shared-app"
    error_message = "Access points must override the Name tag with <rendered_name>-<access point key>."
  }
}

run "verify_name_fallback_when_null" {
  command = plan

  variables {
    name = null
  }

  assert {
    condition     = aws_efs_file_system.this.creation_token == "core-prod"
    error_message = "Creation token must fall back to <application>-<environment> when name is null."
  }

  assert {
    condition     = aws_security_group.this[0].name == "core-prod-efs-sg"
    error_message = "Security group name must fall back to <application>-<environment>-efs-sg when name is null."
  }
}

run "verify_name_fallback_when_empty" {
  command = plan

  variables {
    name = ""
  }

  assert {
    condition     = aws_efs_file_system.this.creation_token == "core-prod"
    error_message = "Creation token must fall back to <application>-<environment> when name is empty."
  }
}

run "verify_tags" {
  command = plan

  variables {
    tags = {
      StorageClass = "SharedPOSIX"
      CostCenter   = "1234"
    }
    access_points = {
      app = {}
    }
  }

  assert {
    condition     = aws_efs_file_system.this.tags["Application"] == "core" && aws_efs_file_system.this.tags["Environment"] == "prod" && aws_efs_file_system.this.tags["Name"] == "core-prod-shared"
    error_message = "File system must carry Application, Environment and Name governance tags."
  }

  assert {
    condition     = aws_efs_file_system.this.tags["StorageClass"] == "SharedPOSIX" && aws_efs_file_system.this.tags["CostCenter"] == "1234"
    error_message = "Caller tags must be preserved on the file system."
  }

  assert {
    condition     = aws_security_group.this[0].tags["Application"] == "core" && aws_security_group.this[0].tags["Environment"] == "prod" && aws_security_group.this[0].tags["StorageClass"] == "SharedPOSIX"
    error_message = "Security group must carry governance and caller tags."
  }

  assert {
    condition     = aws_security_group.this[0].tags["Name"] == "core-prod-shared-efs-sg"
    error_message = "Security group must override the Name tag with its own name."
  }

  assert {
    condition     = aws_efs_access_point.this["app"].tags["Application"] == "core" && aws_efs_access_point.this["app"].tags["Environment"] == "prod" && aws_efs_access_point.this["app"].tags["StorageClass"] == "SharedPOSIX"
    error_message = "Access points must carry governance and caller tags."
  }
}

run "verify_security_defaults" {
  command = plan

  assert {
    condition     = aws_efs_file_system.this.encrypted == true
    error_message = "File system must be encrypted at rest."
  }

  assert {
    condition     = aws_efs_file_system.this.kms_key_id == var.kms_key_arn
    error_message = "File system must be encrypted with the caller-supplied KMS key."
  }

  assert {
    condition     = length(data.aws_iam_policy_document.efs_policy.statement) == 1
    error_message = "File system policy must only contain the TLS deny statement when no client roles are given."
  }

  assert {
    condition     = data.aws_iam_policy_document.efs_policy.statement[0].sid == "DenyUnsecureTransport" && data.aws_iam_policy_document.efs_policy.statement[0].effect == "Deny"
    error_message = "File system policy must start with the DenyUnsecureTransport deny statement."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.efs_policy.statement[0].actions) == toset(["*"])
    error_message = "TLS deny statement must cover every action."
  }

  assert {
    condition     = toset(flatten([for p in data.aws_iam_policy_document.efs_policy.statement[0].principals : [for i in p.identifiers : "${p.type}:${i}"]])) == toset(["AWS:*"])
    error_message = "TLS deny statement must apply to every principal."
  }

  assert {
    condition     = anytrue([for c in data.aws_iam_policy_document.efs_policy.statement[0].condition : c.test == "Bool" && c.variable == "aws:SecureTransport" && c.values == tolist(["false"])])
    error_message = "TLS deny statement must trigger when aws:SecureTransport is false."
  }

  assert {
    condition     = toset([for r in aws_security_group.this[0].ingress : "${r.protocol}:${r.from_port}-${r.to_port}"]) == toset(["tcp:2049-2049"])
    error_message = "Security group must only allow NFS (TCP 2049) inbound."
  }
}

run "verify_file_system_policy_wiring" {
  command = apply

  override_resource {
    target = aws_efs_file_system.this
    values = {
      id  = "fs-0123456789abcdef0"
      arn = "arn:aws:elasticfilesystem:us-west-2:123456789012:file-system/fs-0123456789abcdef0"
    }
  }

  override_resource {
    target = aws_security_group.this
    values = {
      id = "sg-0123456789abcdef0"
    }
  }

  assert {
    condition     = aws_efs_file_system_policy.this.file_system_id == "fs-0123456789abcdef0"
    error_message = "File system policy must be attached to the module's file system."
  }

  assert {
    condition     = aws_efs_file_system_policy.this.policy == data.aws_iam_policy_document.efs_policy.json
    error_message = "File system policy must be rendered from the module's policy document."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.efs_policy.statement[0].resources) == toset(["arn:aws:elasticfilesystem:us-west-2:123456789012:file-system/fs-0123456789abcdef0"])
    error_message = "TLS deny statement must be scoped to the module's file system."
  }

  assert {
    condition     = alltrue([for m in aws_efs_mount_target.this : m.file_system_id == "fs-0123456789abcdef0" && m.security_groups == toset(["sg-0123456789abcdef0"])])
    error_message = "Mount targets must use the module's file system and the module-created security group."
  }

  assert {
    condition     = aws_efs_backup_policy.this.file_system_id == "fs-0123456789abcdef0"
    error_message = "Backup policy must be attached to the module's file system."
  }

  assert {
    condition     = output.id == "fs-0123456789abcdef0" && output.security_group_id == "sg-0123456789abcdef0"
    error_message = "id and security_group_id outputs must expose the file system and security group."
  }

  assert {
    condition     = keys(output.mount_target_ids) == ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
    error_message = "mount_target_ids output must be keyed by subnet id."
  }
}

run "verify_parameter_defaults" {
  command = plan

  assert {
    condition     = aws_efs_file_system.this.performance_mode == "generalPurpose"
    error_message = "Performance mode must default to generalPurpose."
  }

  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "elastic"
    error_message = "Throughput mode must default to elastic."
  }

  assert {
    condition     = aws_efs_file_system.this.provisioned_throughput_in_mibps == null
    error_message = "Provisioned throughput must be unset unless throughput_mode is provisioned."
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 3
    error_message = "IA, archive and back-to-primary lifecycle policies must be configured by default."
  }

  assert {
    condition     = aws_efs_file_system.this.lifecycle_policy[0].transition_to_ia == "AFTER_7_DAYS"
    error_message = "Files must transition to IA after 7 days by default."
  }

  assert {
    condition     = aws_efs_file_system.this.lifecycle_policy[1].transition_to_archive == "AFTER_30_DAYS"
    error_message = "Files must transition to Archive after 30 days by default."
  }

  assert {
    condition     = aws_efs_file_system.this.lifecycle_policy[2].transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "Files must transition back to primary storage after 1 access."
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "ENABLED"
    error_message = "Automatic backups must be enabled by default."
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 2 && toset([for m in aws_efs_mount_target.this : m.subnet_id]) == toset(var.subnet_ids)
    error_message = "One mount target must be created per subnet."
  }

  assert {
    condition     = length(aws_security_group.this) == 1 && aws_security_group.this[0].vpc_id == "vpc-0a1b2c3d4e5f67890"
    error_message = "A dedicated security group must be created in the VPC when no security_group_ids are given."
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 0
    error_message = "No access points must be created by default."
  }
}

run "verify_parameter_overrides" {
  command = plan

  variables {
    performance_mode                = "maxIO"
    throughput_mode                 = "provisioned"
    provisioned_throughput_in_mibps = 128
    transition_to_ia                = "AFTER_30_DAYS"
    transition_to_archive           = null
    enable_backup                   = false
    allowed_security_group_ids      = ["sg-0aaaaaaaaaaaaaaaa"]
    allowed_cidr_blocks             = ["10.0.0.0/16"]
  }

  assert {
    condition     = aws_efs_file_system.this.performance_mode == "maxIO"
    error_message = "performance_mode must flow through to the file system."
  }

  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "provisioned" && aws_efs_file_system.this.provisioned_throughput_in_mibps == 128
    error_message = "Provisioned throughput settings must flow through to the file system."
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 2
    error_message = "The archive lifecycle policy must be omitted when transition_to_archive is null."
  }

  assert {
    condition     = aws_efs_file_system.this.lifecycle_policy[0].transition_to_ia == "AFTER_30_DAYS" && aws_efs_file_system.this.lifecycle_policy[1].transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "transition_to_ia must flow through and the back-to-primary policy must remain."
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "DISABLED"
    error_message = "enable_backup = false must disable the backup policy."
  }

  assert {
    condition     = one(aws_security_group.this[0].ingress).security_groups == toset(["sg-0aaaaaaaaaaaaaaaa"])
    error_message = "allowed_security_group_ids must flow through to the NFS ingress rule."
  }

  assert {
    condition     = one(aws_security_group.this[0].ingress).cidr_blocks == tolist(["10.0.0.0/16"])
    error_message = "allowed_cidr_blocks must flow through to the NFS ingress rule."
  }
}

run "verify_provisioned_throughput_ignored_unless_provisioned" {
  command = plan

  variables {
    throughput_mode                 = "bursting"
    provisioned_throughput_in_mibps = 128
  }

  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "bursting" && aws_efs_file_system.this.provisioned_throughput_in_mibps == null
    error_message = "provisioned_throughput_in_mibps must be ignored unless throughput_mode is provisioned."
  }
}

run "verify_existing_security_groups" {
  command = plan

  variables {
    security_group_ids = ["sg-0bbbbbbbbbbbbbbbb", "sg-0cccccccccccccccc"]
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No security group must be created when security_group_ids are supplied."
  }

  assert {
    condition     = alltrue([for m in aws_efs_mount_target.this : m.security_groups == toset(["sg-0bbbbbbbbbbbbbbbb", "sg-0cccccccccccccccc"])])
    error_message = "Mount targets must use the supplied security groups."
  }

  assert {
    condition     = output.security_group_id == null
    error_message = "security_group_id output must be null when no security group is created."
  }
}

run "verify_client_role_statement" {
  command = plan

  variables {
    allowed_client_role_arns = ["arn:aws:iam::123456789012:role/core-prod-app"]
  }

  assert {
    condition     = length(data.aws_iam_policy_document.efs_policy.statement) == 2
    error_message = "A client access statement must be added when allowed_client_role_arns is set."
  }

  assert {
    condition     = data.aws_iam_policy_document.efs_policy.statement[0].sid == "DenyUnsecureTransport"
    error_message = "The TLS deny statement must remain when client roles are added."
  }

  assert {
    condition     = data.aws_iam_policy_document.efs_policy.statement[1].sid == "AllowClientMountAndWrite" && data.aws_iam_policy_document.efs_policy.statement[1].effect == "Allow"
    error_message = "Client access statement must be an Allow statement with sid AllowClientMountAndWrite."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.efs_policy.statement[1].actions) == toset(["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite", "elasticfilesystem:ClientRootAccess"])
    error_message = "Client access statement must grant mount, write and root access."
  }

  assert {
    condition     = toset(flatten([for p in data.aws_iam_policy_document.efs_policy.statement[1].principals : [for i in p.identifiers : "${p.type}:${i}"]])) == toset(["AWS:arn:aws:iam::123456789012:role/core-prod-app"])
    error_message = "Client access statement must only trust the supplied roles."
  }

  assert {
    condition     = anytrue([for c in data.aws_iam_policy_document.efs_policy.statement[1].condition : c.test == "Bool" && c.variable == "elasticfilesystem:AccessedViaMountTarget" && c.values == tolist(["true"])])
    error_message = "Client access must require access through a mount target."
  }
}

run "verify_access_points" {
  command = plan

  variables {
    access_points = {
      app = {
        posix_user = {
          gid            = 1000
          uid            = 1000
          secondary_gids = [2000]
        }
        root_directory = {
          path = "/app"
          creation_info = {
            owner_gid   = 1000
            owner_uid   = 1000
            permissions = "0750"
          }
        }
      }
      bare = {}
    }
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 2
    error_message = "One access point must be created per entry in access_points."
  }

  assert {
    condition     = aws_efs_access_point.this["app"].posix_user[0].gid == 1000 && aws_efs_access_point.this["app"].posix_user[0].uid == 1000 && aws_efs_access_point.this["app"].posix_user[0].secondary_gids == toset([2000])
    error_message = "Access point POSIX user must flow through."
  }

  assert {
    condition     = aws_efs_access_point.this["app"].root_directory[0].path == "/app"
    error_message = "Access point root directory path must flow through."
  }

  assert {
    condition     = aws_efs_access_point.this["app"].root_directory[0].creation_info[0].owner_uid == 1000 && aws_efs_access_point.this["app"].root_directory[0].creation_info[0].owner_gid == 1000 && aws_efs_access_point.this["app"].root_directory[0].creation_info[0].permissions == "0750"
    error_message = "Access point root directory creation info must flow through."
  }

  assert {
    condition     = length(aws_efs_access_point.this["bare"].posix_user) == 0 && length(aws_efs_access_point.this["bare"].root_directory) == 0
    error_message = "posix_user and root_directory must be omitted when not supplied."
  }
}

run "verify_invalid_application_fails" {
  command = plan

  variables {
    application = "Core_App"
  }

  expect_failures = [var.application]
}

run "verify_invalid_environment_fails" {
  command = plan

  variables {
    environment = "INVALID_UPPERCASE"
  }

  expect_failures = [var.environment]
}

run "verify_invalid_kms_key_arn_fails" {
  command = plan

  variables {
    kms_key_arn = "12345678-1234-1234-1234-123456789012"
  }

  expect_failures = [var.kms_key_arn]
}

run "verify_invalid_performance_mode_fails" {
  command = plan

  variables {
    performance_mode = "turbo"
  }

  expect_failures = [var.performance_mode]
}

run "verify_invalid_throughput_mode_fails" {
  command = plan

  variables {
    throughput_mode = "burst"
  }

  expect_failures = [var.throughput_mode]
}
