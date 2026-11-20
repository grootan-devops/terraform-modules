output "compute_environment_arns" {
  description = "Compute environment ARNs by key."
  value       = { for k, c in aws_batch_compute_environment.this : k => c.arn }
}

output "compute_environment_names" {
  description = "Compute environment names by key."
  value       = { for k, c in aws_batch_compute_environment.this : k => c.name }
}

output "job_queue_arns" {
  description = "Job queue ARNs by key."
  value       = { for k, q in aws_batch_job_queue.this : k => q.arn }
}

output "job_queue_names" {
  description = "Job queue names by key (JobQueue dimension)."
  value       = { for k, q in aws_batch_job_queue.this : k => q.name }
}

output "job_definition_arns" {
  description = "Job definition ARNs (latest revision) by key."
  value       = { for k, d in aws_batch_job_definition.this : k => d.arn }
}

output "job_definition_arn_prefixes" {
  description = "Job definition ARNs without revision by key."
  value       = { for k, d in aws_batch_job_definition.this : k => d.arn_prefix }
}

output "scheduling_policy_arn" {
  description = "Scheduling policy ARN; null when disabled."
  value       = try(aws_batch_scheduling_policy.this[0].arn, null)
}

output "security_group_id" {
  description = "Compute environment security group ID; null without one."
  value       = try(module.security_group[0].id, null)
}

output "role_arn" {
  description = "Job role ARN; null without job definitions."
  value       = local.has_jobs ? local.job_role_arn : null
}

output "role_name" {
  description = "Job role name; null for a role brought by the caller."
  value       = try(module.job_role[0].name, null)
}

output "execution_role_arn" {
  description = "Execution role ARN; null without job definitions."
  value       = try(module.execution_role[0].arn, null)
}

output "log_group_name" {
  description = "Log group name; null when disabled."
  value       = try(module.log_group[0].name, null)
}

output "log_group_arn" {
  description = "Log group ARN; null when disabled."
  value       = try(module.log_group[0].arn, null)
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}
