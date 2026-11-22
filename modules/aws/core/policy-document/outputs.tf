output "json" {
  description = "Policy JSON."
  value       = jsonencode({ Version = "2012-10-17", Statement = local.statements })
}

output "statements_json" {
  description = "Rendered statements as a JSON list."
  value       = jsonencode(local.rendered)
}

output "statement_count" {
  description = "Statement count."
  value       = length(local.statements)
}
