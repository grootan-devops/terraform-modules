output "id" {
  description = "ID of the EFS file system."
  value       = aws_efs_file_system.this.id
}

output "arn" {
  description = "ARN of the EFS file system."
  value       = aws_efs_file_system.this.arn
}

output "dns_name" {
  description = "DNS name of the EFS file system."
  value       = aws_efs_file_system.this.dns_name
}

output "mount_target_ids" {
  description = "Map of subnet IDs to mount target IDs."
  value       = { for k, v in aws_efs_mount_target.this : k => v.id }
}

output "security_group_id" {
  description = "ID of the created EFS security group (if created)."
  value       = try(aws_security_group.this[0].id, null)
}

output "access_points" {
  description = "Map of created EFS access points."
  value       = { for k, v in aws_efs_access_point.this : k => { id = v.id, arn = v.arn } }
}
