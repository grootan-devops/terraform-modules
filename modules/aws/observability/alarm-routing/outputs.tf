output "topic_arns" {
  description = "Topic ARN by Region, then severity."
  value       = { for r in local.regions : r => { for s in local.severities : s => aws_sns_topic.this["${r}/${s}"].arn } }

  depends_on = [aws_sns_topic_policy.this]
}

output "email_subscription_arns" {
  description = "Email subscription ARN by region/severity/address."
  value       = { for k, s in aws_sns_topic_subscription.email : k => s.arn }
}

output "https_subscription_arns" {
  description = "HTTPS subscription ARN by region/severity/index."
  value       = { for k, s in aws_sns_topic_subscription.https : k => s.arn }
}

output "kms_key_arns" {
  description = "Topic key ARN by Region."
  value       = { for r in local.regions : r => module.encryption[r].key_arn }
}
