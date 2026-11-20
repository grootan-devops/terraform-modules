module "naming" {
  source = "../../core/naming"

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags
  names = {
    file_system = { max_length = 64 }
  }
}

module "encryption" {
  source = "../../core/encryption"

  application = var.application
  environment = var.environment
  name        = var.name
  purpose     = "efs"
  tags        = var.tags
  kms         = var.kms
}

module "security_group" {
  source = "../../network/security-group"
  count  = var.security_group.create ? 1 : 0

  application   = var.application
  environment   = var.environment
  name          = var.name
  purpose       = "efs"
  tags          = var.tags
  vpc_id        = var.vpc_id
  ingress_rules = local.ingress_rules
}

module "policy" {
  source = "../../core/policy-document"

  default_resources = [aws_efs_file_system.this.arn]
  statements        = concat(local.guard_statements, var.policy_statements)
}

resource "aws_efs_file_system" "this" {
  creation_token                  = local.name
  encrypted                       = true
  kms_key_id                      = local.kms_key_arn
  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput.mode
  provisioned_throughput_in_mibps = var.throughput.provisioned_mibps

  dynamic "lifecycle_policy" {
    for_each = local.transitions

    content {
      transition_to_ia                    = lifecycle_policy.key == "transition_to_ia" ? lifecycle_policy.value : null
      transition_to_archive               = lifecycle_policy.key == "transition_to_archive" ? lifecycle_policy.value : null
      transition_to_primary_storage_class = lifecycle_policy.key == "transition_to_primary_storage_class" ? lifecycle_policy.value : null
    }
  }

  tags = merge(module.naming.tags, { Name = local.name })
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = var.backup.enabled ? "ENABLED" : "DISABLED"
  }
}

resource "aws_efs_file_system_policy" "this" {
  file_system_id                     = aws_efs_file_system.this.id
  policy                             = module.policy.json
  bypass_policy_lockout_safety_check = false
}

resource "aws_efs_mount_target" "this" {
  count = length(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = var.subnet_ids[count.index]
  security_groups = local.security_group_ids
}

resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  posix_user {
    uid            = each.value.uid
    gid            = each.value.gid
    secondary_gids = each.value.secondary_gids
  }

  root_directory {
    path = each.value.path

    creation_info {
      owner_uid   = each.value.uid
      owner_gid   = each.value.gid
      permissions = each.value.permissions
    }
  }

  tags = merge(module.naming.tags, { Name = "${local.name}-${each.key}" })
}
