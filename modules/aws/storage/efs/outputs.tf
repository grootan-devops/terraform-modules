output "id" {
  description = "File system ID."
  value       = aws_efs_file_system.this.id
}

output "arn" {
  description = "File system ARN."
  value       = aws_efs_file_system.this.arn
}

output "name" {
  description = "File system name."
  value       = local.name
}

output "dns_name" {
  description = "File system DNS name."
  value       = aws_efs_file_system.this.dns_name
}

output "security_group_id" {
  description = "Mount target security group ID; null when not created."
  value       = one(module.security_group[*].id)
}

output "access_point_ids" {
  description = "Access point IDs by key."
  value       = { for k, ap in aws_efs_access_point.this : k => ap.id }
}

output "access_point_arns" {
  description = "Access point ARNs by key."
  value       = { for k, ap in aws_efs_access_point.this : k => ap.arn }
}

output "kms_key_arn" {
  description = "Key ARN in use; null for the AWS managed key."
  value       = local.kms_key_arn
}
