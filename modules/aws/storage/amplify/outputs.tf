output "app_id" {
  description = "Unique ID of the Amplify App."
  value       = aws_amplify_app.this.id
}

output "app_arn" {
  description = "ARN of the Amplify App."
  value       = aws_amplify_app.this.arn
}

output "default_domain" {
  description = "Default domain for the Amplify App."
  value       = aws_amplify_app.this.default_domain
}

output "branch_arns" {
  description = "Map of branch names to branch ARNs."
  value       = { for k, b in aws_amplify_branch.this : k => b.arn }
}
