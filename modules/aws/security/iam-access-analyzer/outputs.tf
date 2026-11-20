output "external_analyzer_arns" {
  description = "External access analyzer ARNs by Region."
  value       = { for region, analyzer in aws_accessanalyzer_analyzer.external : region => analyzer.arn }
}

output "unused_access_analyzer_arn" {
  description = "Unused access analyzer ARN; null when off."
  value       = try(aws_accessanalyzer_analyzer.unused[0].arn, null)
}

output "internal_access_analyzer_arn" {
  description = "Internal access analyzer ARN; null when off."
  value       = try(aws_accessanalyzer_analyzer.internal[0].arn, null)
}

output "analyzer_names" {
  description = "Names of the analyzers this call creates, by kind."
  value       = { for kind, name in module.naming.names : kind => name if local.analyzer_created[kind] }
}
