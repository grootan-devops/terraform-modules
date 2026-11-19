output "graph_arns" {
  description = "Behavior graph ARN by Region."
  value       = { for region, graph in aws_detective_graph.this : region => graph.graph_arn }
}

output "member_ids" {
  description = "Member ID by account_id/region key."
  value       = { for key, member in aws_detective_member.this : key => member.id }
}

output "member_statuses" {
  description = "Member status by account_id/region key."
  value       = { for key, member in aws_detective_member.this : key => member.status }
}
