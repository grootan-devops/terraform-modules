output "cluster_id" {
  description = "ID of the ECS cluster."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN that identifies the cluster."
  value       = aws_ecs_cluster.this.arn
}

output "service_names" {
  description = "Map of service names."
  value       = { for k, v in aws_ecs_service.this : k => v.name }
}

output "service_ids" {
  description = "Map of service IDs."
  value       = { for k, v in aws_ecs_service.this : k => v.id }
}

output "task_definition_arns" {
  description = "Map of Task Definition ARNs."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role."
  value       = try(aws_iam_role.task_execution[0].arn, null)
}

output "service_task_role_arns" {
  description = "Map of service task role ARNs."
  value       = { for k, v in aws_iam_role.service_task : k => v.arn }
}

output "security_group_id" {
  description = "Security group ID attached to the ECS service."
  value       = try(aws_security_group.service[0].id, null)
}
