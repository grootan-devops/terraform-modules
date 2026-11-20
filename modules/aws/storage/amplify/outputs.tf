output "id" {
  description = "App ID."
  value       = aws_amplify_app.this.id
}

output "arn" {
  description = "App ARN."
  value       = aws_amplify_app.this.arn
}

output "name" {
  description = "App name."
  value       = aws_amplify_app.this.name
}

output "default_domain" {
  description = "Default amplifyapp.com domain."
  value       = aws_amplify_app.this.default_domain
}

output "branch_names" {
  description = "Branch names."
  value       = [for b in aws_amplify_branch.this : b.branch_name]
}

output "domain_dns_records" {
  description = "Certificate verification and sub-domain DNS records by domain."
  value = {
    for d, a in aws_amplify_domain_association.this : d => {
      certificate_verification = a.certificate_verification_dns_record
      sub_domains              = { for s in a.sub_domain : s.prefix => s.dns_record }
    }
  }
}
