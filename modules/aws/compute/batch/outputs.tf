output "job_queue_arns" {
  description = "Map of Job Queue ARNs to be used with EventBridge targets."
  value       = { for k, v in aws_batch_job_queue.this : k => v.arn }
}

output "job_definition_arns" {
  description = "Map of Job Definition ARNs to be used with EventBridge targets."
  value       = { for k, v in aws_batch_job_definition.this : k => v.arn }
}

output "eventbridge_role_arn" {
  description = "The IAM Role ARN required by EventBridge / Scheduler to trigger these Batch jobs."
  value       = aws_iam_role.eventbridge_batch.arn
}
