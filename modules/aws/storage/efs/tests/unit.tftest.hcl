mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "eu-west-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_resource "aws_efs_file_system" {
    defaults = {
      id       = "fs-0123456789abcdef0"
      arn      = "arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0123456789abcdef0"
      dns_name = "fs-0123456789abcdef0.efs.eu-west-1.amazonaws.com"
    }
  }

  mock_resource "aws_security_group" {
    defaults = {
      id = "sg-0eeeeeeeeeeeeeeee"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    }
  }
}

variables {
  application = "core"
  environment = "prod"
  name        = "shared"
  tags        = { Team = "platform" }
  vpc_id      = "vpc-0a1b2c3d4e5f67890"
  subnet_ids  = ["subnet-0123456789abcdef0", "subnet-0fedcba9876543210"]
  security_group = {
    ingress_security_group_ids = ["sg-0aaaaaaaaaaaaaaaa"]
  }
}

run "secure_defaults" {
  command = plan

  assert {
    condition     = aws_efs_file_system.this.creation_token == "core-prod-shared" && aws_efs_file_system.this.tags["Name"] == "core-prod-shared" && aws_efs_file_system.this.tags["Team"] == "platform" && aws_efs_file_system.this.tags["ManagedBy"] == "Terraform"
    error_message = "The file system is <application>-<environment>-<name> with caller and governance tags."
  }

  assert {
    condition     = aws_efs_file_system.this.encrypted && output.kms_key_arn == null
    error_message = "No kms input means the AWS managed key, always encrypted (EFS.1)."
  }

  assert {
    condition     = aws_efs_file_system.this.performance_mode == "generalPurpose" && aws_efs_file_system.this.throughput_mode == "elastic" && aws_efs_file_system.this.provisioned_throughput_in_mibps == null
    error_message = "Defaults: generalPurpose, elastic throughput."
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 3
    error_message = "IA, archive and back-to-primary transitions by default."
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "DISABLED"
    error_message = "storage/backup owns backups; EFS automatic backups are off."
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 2 && aws_efs_mount_target.this[1].subnet_id == "subnet-0fedcba9876543210" && length(aws_efs_access_point.this) == 0
    error_message = "One mount target per subnet, no access points by default."
  }

  assert {
    condition     = length(module.security_group) == 1
    error_message = "The module creates the mount target security group."
  }
}

run "module_key_is_planned_safely" {
  command = plan

  variables {
    kms = { create = true }
  }

  assert {
    condition     = module.encryption.created
    error_message = "kms.create must plan without knowing the key ARN."
  }
}

run "file_system_policy_and_security_group" {
  command = apply

  variables {
    kms = { create = true }
    security_group = {
      ingress_security_group_ids    = ["sg-0aaaaaaaaaaaaaaaa"]
      ingress_cidr_blocks           = ["10.0.0.0/16", "fd00::/8"]
      ingress_prefix_list_ids       = ["pl-0123456789abcdef0"]
      additional_security_group_ids = ["sg-0bbbbbbbbbbbbbbbb"]
    }
  }

  assert {
    condition     = aws_efs_file_system.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555" && output.kms_key_arn == aws_efs_file_system.this.kms_key_id
    error_message = "The module key must encrypt the file system."
  }

  assert {
    condition     = [for s in jsondecode(module.policy.json).Statement : s.Sid] == ["DenyInsecureTransport", "AllowClientAccessThroughMountTargets"] && jsondecode(module.policy.json).Statement[0].Condition.Bool["aws:SecureTransport"] == ["false"]
    error_message = "The policy denies requests without TLS first."
  }

  assert {
    condition     = jsondecode(module.policy.json).Statement[1].Action == ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"] && jsondecode(module.policy.json).Statement[1].Condition.Bool["elasticfilesystem:AccessedViaMountTarget"] == ["true"] && jsondecode(module.policy.json).Statement[1].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0123456789abcdef0"]
    error_message = "Clients mount and write through mount targets only; root is squashed."
  }

  assert {
    condition     = keys(module.security_group[0].ingress_rule_ids) == ["cidr-0", "cidr-1", "pl-0", "sg-0"] && length(module.security_group[0].egress_rule_ids) == 0
    error_message = "NFS ingress from every listed source and no egress."
  }

  assert {
    condition     = toset(aws_efs_mount_target.this[0].security_groups) == toset(["sg-0eeeeeeeeeeeeeeee", "sg-0bbbbbbbbbbbbbbbb"]) && output.security_group_id == "sg-0eeeeeeeeeeeeeeee"
    error_message = "Mount targets use the module group and the extra group."
  }
}

run "client_access_and_extra_statements" {
  command   = apply
  state_key = "clients"

  variables {
    client_access     = { principal_arns = ["arn:aws:iam::123456789012:role/core-prod-api-task-eu-west-1"], read_only = true }
    policy_statements = [{ sid = "AllowBackup", actions = ["elasticfilesystem:Backup"], principals = { AWS = ["arn:aws:iam::123456789012:role/backup"] } }]
  }

  assert {
    condition     = jsondecode(module.policy.json).Statement[1].Principal.AWS == ["arn:aws:iam::123456789012:role/core-prod-api-task-eu-west-1"] && jsondecode(module.policy.json).Statement[1].Action == ["elasticfilesystem:ClientMount"]
    error_message = "principal_arns and read_only narrow client access."
  }

  assert {
    condition     = jsondecode(module.policy.json).Statement[2].Sid == "AllowBackup" && jsondecode(module.policy.json).Statement[2].Resource == ["arn:aws:elasticfilesystem:eu-west-1:123456789012:file-system/fs-0123456789abcdef0"]
    error_message = "Caller statements follow and default to the file system."
  }
}

run "root_access" {
  command   = apply
  state_key = "root"

  variables {
    client_access = { root_access = true }
  }

  assert {
    condition     = contains(jsondecode(module.policy.json).Statement[1].Action, "elasticfilesystem:ClientRootAccess")
    error_message = "root_access grants ClientRootAccess."
  }
}

run "access_points" {
  command   = apply
  state_key = "access_points"

  variables {
    access_points = {
      app = { uid = 1000, gid = 1000, path = "/app" }
      ml  = { uid = 2000, gid = 2000, secondary_gids = [3000], path = "/data/ml", permissions = "0700" }
    }
  }

  assert {
    condition     = aws_efs_access_point.this["app"].posix_user[0].uid == 1000 && aws_efs_access_point.this["app"].root_directory[0].path == "/app" && aws_efs_access_point.this["app"].root_directory[0].creation_info[0].permissions == "0750"
    error_message = "Access points enforce the POSIX user and a root directory (EFS.3, EFS.4)."
  }

  assert {
    condition     = aws_efs_access_point.this["ml"].root_directory[0].creation_info[0].owner_uid == 2000 && aws_efs_access_point.this["ml"].tags["Name"] == "core-prod-shared-ml"
    error_message = "The root directory is owned by the POSIX user."
  }

  assert {
    condition     = keys(output.access_point_arns) == ["app", "ml"] && keys(output.access_point_ids) == ["app", "ml"]
    error_message = "Access point IDs and ARNs are exported by key."
  }
}

run "caller_key_and_own_security_group" {
  command = plan

  variables {
    kms            = { key_id = "11111111-2222-3333-4444-555555555555" }
    security_group = { create = false, additional_security_group_ids = ["sg-0ccccccccccccccccc"] }
  }

  assert {
    condition     = aws_efs_file_system.this.kms_key_id == "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    error_message = "A key ID must be used as the key ARN."
  }

  assert {
    condition     = length(module.security_group) == 0 && output.security_group_id == null && toset(aws_efs_mount_target.this[0].security_groups) == toset(["sg-0ccccccccccccccccc"])
    error_message = "A caller group must replace the module group."
  }
}

run "throughput_backup_and_transitions" {
  command = plan

  variables {
    throughput       = { mode = "provisioned", provisioned_mibps = 128 }
    backup           = { enabled = true }
    lifecycle_policy = { transition_to_archive = "NONE" }
  }

  assert {
    condition     = aws_efs_file_system.this.throughput_mode == "provisioned" && aws_efs_file_system.this.provisioned_throughput_in_mibps == 128
    error_message = "Provisioned throughput must apply."
  }

  assert {
    condition     = aws_efs_backup_policy.this.backup_policy[0].status == "ENABLED" && length(aws_efs_file_system.this.lifecycle_policy) == 2
    error_message = "backup.enabled turns EFS backups on; a null transition is dropped."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Shared_FS"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_application" {
  command = plan

  variables {
    application = "Core"
  }

  expect_failures = [var.application]
}

run "rejects_invalid_environment" {
  command = plan

  variables {
    environment = "PROD"
  }

  expect_failures = [var.environment]
}

run "rejects_no_subnets" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "rejects_no_security_group" {
  command = plan

  variables {
    security_group = { create = false }
  }

  expect_failures = [var.security_group]
}

run "rejects_open_ingress" {
  command = plan

  variables {
    security_group = { ingress_cidr_blocks = ["0.0.0.0/0"] }
  }

  expect_failures = [var.security_group]
}

run "rejects_create_and_key_id" {
  command = plan

  variables {
    kms = { create = true, key_id = "11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_key_id" {
  command = plan

  variables {
    kms = { key_id = "alias/efs" }
  }

  expect_failures = [var.kms]
}

run "rejects_invalid_performance_mode" {
  command = plan

  variables {
    performance_mode = "turbo"
  }

  expect_failures = [var.performance_mode]
}

run "rejects_invalid_throughput_mode" {
  command = plan

  variables {
    throughput = { mode = "max" }
  }

  expect_failures = [var.throughput]
}

run "rejects_provisioned_without_mibps" {
  command = plan

  variables {
    throughput = { mode = "provisioned" }
  }

  expect_failures = [var.throughput]
}

run "rejects_invalid_transition" {
  command = plan

  variables {
    lifecycle_policy = { transition_to_ia = "AFTER_2_DAYS" }
  }

  expect_failures = [var.lifecycle_policy]
}

run "rejects_invalid_primary_transition" {
  command = plan

  variables {
    lifecycle_policy = { transition_to_primary_storage_class = "AFTER_2_ACCESSES" }
  }

  expect_failures = [var.lifecycle_policy]
}

run "rejects_root_path_access_point" {
  command = plan

  variables {
    access_points = { root = { uid = 0, gid = 0, path = "/" } }
  }

  expect_failures = [var.access_points]
}

run "rejects_invalid_permissions" {
  command = plan

  variables {
    access_points = { app = { uid = 1000, gid = 1000, path = "/app", permissions = "rwx" } }
  }

  expect_failures = [var.access_points]
}
