output "arn" {
  description = "Certificate ARN, after validation when enabled."
  value       = local.certificate_arn
}

output "domain_name" {
  description = "Certificate domain name."
  value       = aws_acm_certificate.this.domain_name
}

output "status" {
  description = "Certificate status."
  value       = aws_acm_certificate.this.status
}

output "validation_record_fqdns" {
  description = "Validation record FQDNs."
  value       = [for r in aws_route53_record.validation : r.fqdn]
}

output "validation_records" {
  description = "Validation records for external DNS: name, type, value."
  value       = [for o in aws_acm_certificate.this.domain_validation_options : { name = o.resource_record_name, type = o.resource_record_type, value = o.resource_record_value }]
}
