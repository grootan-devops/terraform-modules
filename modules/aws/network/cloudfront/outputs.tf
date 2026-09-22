output "id" {
  description = "Identifier of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.id
}

output "arn" {
  description = "ARN of the CloudFront distribution."
  value       = aws_cloudfront_distribution.this.arn
}

output "domain_name" {
  description = "Domain name corresponding to the distribution."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "hosted_zone_id" {
  description = "CloudFront Route 53 zone ID that can be used to route an Alias resource to."
  value       = aws_cloudfront_distribution.this.hosted_zone_id
}
