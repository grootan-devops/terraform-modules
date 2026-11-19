output "arn" {
  description = "Cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "name" {
  description = "Cluster name (ClusterName dimension)."
  value       = aws_ecs_cluster.this.name
}

output "service_names" {
  description = "Service names by key (ServiceName dimension)."
  value       = { for k, s in aws_ecs_service.this : k => s.name }
}

output "service_arns" {
  description = "Service ARNs by key."
  value       = { for k, s in aws_ecs_service.this : k => s.arn }
}

output "task_definition_arns" {
  description = "Task definition ARNs by key."
  value       = { for k, t in aws_ecs_task_definition.this : k => t.arn }
}

output "execution_role_arn" {
  description = "Execution role ARN; null without services."
  value       = try(module.execution_role[0].arn, null)
}

output "task_role_arns" {
  description = "Task role ARNs by service key."
  value       = local.task_role_arns
}

output "task_role_names" {
  description = "Module task role names by service key."
  value       = { for k, r in module.task_role : k => r.name }
}

output "security_group_id" {
  description = "Task security group ID; null without one."
  value       = try(module.security_group[0].id, null)
}

output "log_group_names" {
  description = "Service log group names by key."
  value       = { for k, l in module.log_group : k => l.name }
}

output "log_group_arns" {
  description = "Service log group ARNs by key."
  value       = { for k, l in module.log_group : k => l.arn }
}

output "exec_log_group_name" {
  description = "ECS Exec log group name; null without ECS Exec."
  value       = try(module.exec_log_group[0].name, null)
}

output "service_discovery_namespace_arn" {
  description = "Cloud Map namespace ARN; null without discovery."
  value       = try(aws_service_discovery_private_dns_namespace.this[0].arn, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}
