resource "aws_efs_file_system" "this" {
  creation_token = local.name_prefix

  encrypted                       = true
  kms_key_id                      = var.kms_key_arn
  performance_mode                = var.performance_mode
  throughput_mode                 = var.throughput_mode
  provisioned_throughput_in_mibps = var.throughput_mode == "provisioned" ? var.provisioned_throughput_in_mibps : null

  lifecycle_policy {
    transition_to_ia = var.transition_to_ia
  }

  dynamic "lifecycle_policy" {
    for_each = var.transition_to_archive != null ? [1] : []
    content {
      transition_to_archive = var.transition_to_archive
    }
  }

  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = local.tags
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = var.enable_backup ? "ENABLED" : "DISABLED"
  }
}

resource "aws_efs_mount_target" "this" {
  for_each = toset(var.subnet_ids)

  file_system_id  = aws_efs_file_system.this.id
  subnet_id       = each.key
  security_groups = length(var.security_group_ids) > 0 ? var.security_group_ids : [aws_security_group.this[0].id]
}

resource "aws_efs_access_point" "this" {
  for_each = var.access_points

  file_system_id = aws_efs_file_system.this.id

  dynamic "posix_user" {
    for_each = each.value.posix_user != null ? [each.value.posix_user] : []
    content {
      gid            = posix_user.value.gid
      uid            = posix_user.value.uid
      secondary_gids = try(posix_user.value.secondary_gids, null)
    }
  }

  dynamic "root_directory" {
    for_each = each.value.root_directory != null ? [each.value.root_directory] : []
    content {
      path = try(root_directory.value.path, "/${each.key}")
      dynamic "creation_info" {
        for_each = try(root_directory.value.creation_info, null) != null ? [root_directory.value.creation_info] : []
        content {
          owner_gid   = creation_info.value.owner_gid
          owner_uid   = creation_info.value.owner_uid
          permissions = creation_info.value.permissions
        }
      }
    }
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })
}
