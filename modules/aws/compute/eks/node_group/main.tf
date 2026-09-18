resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name         = var.cluster_name
  node_group_name      = "${local.name_prefix}-${each.key}"
  node_role_arn        = aws_iam_role.node_group.arn
  subnet_ids           = each.value.subnet_ids
  ami_type             = coalesce(each.value.ami_type, "AL2023_x86_64_STANDARD")
  capacity_type        = coalesce(each.value.capacity_type, "ON_DEMAND")
  release_version      = each.value.ami_release_version
  force_update_version = true
  instance_types       = each.value.instance_types
  labels               = each.value.labels

  launch_template {
    id      = aws_launch_template.eks_node_group[each.key].id
    version = tostring(aws_launch_template.eks_node_group[each.key].latest_version)
  }

  dynamic "taint" {
    for_each = coalesce(each.value.taints, [])
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  scaling_config {
    min_size     = each.value.scaling_config.min_size
    max_size     = each.value.scaling_config.max_size
    desired_size = each.value.scaling_config.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_registry
  ]
}

resource "aws_launch_template" "eks_node_group" {
  for_each = var.node_groups

  name = "${local.name_prefix}-node-${each.key}"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = coalesce(try(each.value.root_volume.size, null), 50)
      iops                  = try(each.value.root_volume.iops, null)
      throughput            = try(each.value.root_volume.throughput, null)
      encrypted             = true
      kms_key_id            = var.kms_key_arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-${each.key}" })
  }
}
