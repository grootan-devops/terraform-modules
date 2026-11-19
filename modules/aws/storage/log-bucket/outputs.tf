output "id" {
  description = "Bucket ID."
  value       = module.bucket.id
}

output "arn" {
  description = "Bucket ARN."
  value       = module.bucket.arn
}

output "name" {
  description = "Bucket name."
  value       = module.bucket.name
}

output "domain_name" {
  description = "Bucket domain name."
  value       = module.bucket.domain_name
}
