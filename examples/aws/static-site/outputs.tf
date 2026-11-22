output "url" {
  description = "Site URL."
  value       = "https://${var.domain_name}"
}

output "admin_url" {
  description = "Admin console URL."
  value       = "https://admin.${var.domain_name}"
}

output "site_bucket" {
  description = "Site bucket name."
  value       = module.site.name
}

output "log_bucket" {
  description = "Log bucket name."
  value       = module.logs.name
}

output "distribution_domain_name" {
  description = "CloudFront domain name."
  value       = module.cdn.domain_name
}

output "web_acl_name" {
  description = "CloudFront web ACL name."
  value       = module.edge_waf.name
}

output "edge_log_groups" {
  description = "CloudFront and WAF log groups in us-east-1."
  value       = [module.cdn.log_group_name, module.edge_waf.log_group_name]
}

output "admin_app_name" {
  description = "Amplify app name."
  value       = module.admin.name
}
