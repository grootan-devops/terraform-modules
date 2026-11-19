module "alarms" {
  source = "../../observability/cloudwatch-alarms"
  count  = var.alarms.enabled ? 1 : 0

  application = var.application
  environment = var.environment
  name        = var.name
  tags        = var.tags

  notifications = {
    enabled    = length(var.alarms.topic_arns) > 0
    topic_arns = { (module.naming.region) = var.alarms.topic_arns }
  }

  eks_clusters = {
    cluster = {
      cluster_name       = aws_eks_cluster.this.name
      container_insights = var.container_insights.enabled
      alarms             = var.alarms.overrides.cluster
    }
  }

  auto_scaling_groups = {
    for k, n in aws_eks_node_group.this : k => {
      auto_scaling_group_name = n.resources[0].autoscaling_groups[0].name
      alarms                  = var.alarms.overrides.node_groups
    }
  }
}
