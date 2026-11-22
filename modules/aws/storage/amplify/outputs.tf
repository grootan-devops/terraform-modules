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
  description = "DNS records by domain: certificate verification and sub-domains as name, type, value."
  value = {
    for d, a in aws_amplify_domain_association.this : d => {
      certificate_verification = try(zipmap(["name", "type", "value"], compact(split(" ", a.certificate_verification_dns_record))), null)
      sub_domains = {
        for s in a.sub_domain : s.prefix => {
          name  = s.prefix
          type  = try(reverse(compact(split(" ", s.dns_record)))[1], null)
          value = try(reverse(compact(split(" ", s.dns_record)))[0], null)
        }
      }
    }
  }
}
