output "arn" {
  description = "Role ARN."
  value       = aws_iam_role.this.arn
}

output "name" {
  description = "Role name."
  value       = aws_iam_role.this.name
}

output "id" {
  description = "Role unique ID."
  value       = aws_iam_role.this.unique_id
}

output "instance_profile_arn" {
  description = "Instance profile ARN."
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}

output "instance_profile_name" {
  description = "Instance profile name."
  value       = try(aws_iam_instance_profile.this[0].name, null)
}

output "policy_json" {
  description = "Inline policy JSON; null without one."
  value       = local.has_inline_policy ? module.policy.json : null
}

output "trust_policy_json" {
  description = "Trust policy JSON."
  value       = local.trust_policy
}
