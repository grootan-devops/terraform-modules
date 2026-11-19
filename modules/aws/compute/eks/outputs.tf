output "name" {
  description = "Cluster name."
  value       = aws_eks_cluster.this.name
}

output "arn" {
  description = "Cluster ARN."
  value       = aws_eks_cluster.this.arn
}

output "endpoint" {
  description = "Kubernetes API endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "certificate_authority_data" {
  description = "Base64 cluster CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL."
  value       = try(aws_eks_cluster.this.identity[0].oidc[0].issuer, null)
}

output "cluster_security_group_id" {
  description = "EKS-managed cluster security group ID."
  value       = aws_eks_cluster.this.vpc_config[0].cluster_security_group_id
}

output "security_group_id" {
  description = "Module API security group ID; null without one."
  value       = try(module.security_group[0].id, null)
}

output "cluster_role_arn" {
  description = "Cluster role ARN."
  value       = module.cluster_role.arn
}

output "node_role_arn" {
  description = "Node role ARN; null without node groups."
  value       = local.has_nodes ? local.node_role_arn : null
}

output "node_role_name" {
  description = "Node role name; null for a role brought by the caller."
  value       = try(module.node_role[0].name, null)
}

output "node_group_names" {
  description = "Node group names by key."
  value       = { for k, n in aws_eks_node_group.this : k => n.node_group_name }
}

output "autoscaling_group_names" {
  description = "Auto Scaling group names by node group key."
  value       = { for k, n in aws_eks_node_group.this : k => flatten([for r in n.resources : [for a in r.autoscaling_groups : a.name]]) }
}

output "launch_template_ids" {
  description = "Launch template IDs by node group key."
  value       = { for k, t in aws_launch_template.this : k => t.id }
}

output "fargate_role_arn" {
  description = "Fargate pod execution role ARN; null without profiles."
  value       = try(module.fargate_role[0].arn, null)
}

output "pod_identity_role_arns" {
  description = "Workload Pod Identity role ARNs by key."
  value       = { for k, p in var.pod_identities : k => contains(keys(local.workload_roles), k) ? module.workload_role[k].arn : p.role_arn }
}

output "log_group_name" {
  description = "Control plane log group name; null without log types."
  value       = try(module.log_group[0].name, null)
}

output "log_group_arn" {
  description = "Control plane log group ARN; null without log types."
  value       = try(module.log_group[0].arn, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}
