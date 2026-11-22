resource "aws_launch_template" "this" {
  for_each = var.node_groups

  name_prefix            = "${module.naming.names["ng-${each.key}"]}-"
  description            = "${module.naming.names["ng-${each.key}"]} EKS nodes"
  update_default_version = true

  block_device_mappings {
    device_name = startswith(each.value.ami_type, "BOTTLEROCKET") ? "/dev/xvdb" : "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = each.value.disk_size
      iops                  = each.value.disk_iops
      throughput            = each.value.disk_throughput
      encrypted             = "true"
      kms_key_id            = local.kms_key_arn
      delete_on_termination = "true"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(module.naming.tags, { Name = module.naming.names["ng-${each.key}"] })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(module.naming.tags, { Name = module.naming.names["ng-${each.key}"] })
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["ng-${each.key}"] })
}

resource "aws_eks_node_group" "this" {
  for_each = var.node_groups

  cluster_name           = aws_eks_cluster.this.name
  node_group_name_prefix = "${module.naming.names["ng-${each.key}"]}-"
  node_role_arn          = local.node_role_arn
  subnet_ids             = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids
  version                = each.value.release_version == null ? aws_eks_cluster.this.version : null
  release_version        = each.value.release_version
  ami_type               = each.value.ami_type
  capacity_type          = each.value.capacity_type
  instance_types         = each.value.instance_types
  labels                 = each.value.labels

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = tostring(aws_launch_template.this[each.key].latest_version)
  }

  scaling_config {
    min_size     = each.value.min_size
    max_size     = each.value.max_size
    desired_size = coalesce(each.value.desired_size, each.value.min_size)
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["ng-${each.key}"] })

  depends_on = [module.node_role, aws_eks_addon.before_compute]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}

resource "aws_eks_fargate_profile" "this" {
  for_each = var.fargate_profiles

  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = module.naming.names["fp-${each.key}"]
  pod_execution_role_arn = module.fargate_role[0].arn
  subnet_ids             = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids

  dynamic "selector" {
    for_each = each.value.selectors
    content {
      namespace = selector.value.namespace
      labels    = selector.value.labels
    }
  }

  tags = merge(module.naming.tags, { Name = module.naming.names["fp-${each.key}"] })
}
