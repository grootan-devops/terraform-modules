output "id" {
  description = "Distribution ID."
  value       = aws_cloudfront_distribution.this.id
}

output "arn" {
  description = "Distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Distribution domain name."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "Route 53 zone ID for alias records."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}

output "log_group_name" {
  description = "Access log group name."
  value       = module.log_group.name
}

output "log_group_arn" {
  description = "Access log group ARN."
  value       = module.log_group.arn
}

output "kms_key_arn" {
  description = "Log key ARN; null for service encryption."
  value       = local.kms_key_arn
}
