output "node_group_arns" {
  description = "Map of node group keys to their resource ARNs."
  value       = { for k, v in aws_eks_node_group.this : k => v.arn }
}

output "node_group_ids" {
  description = "Map of node group keys to their resource IDs."
  value       = { for k, v in aws_eks_node_group.this : k => v.id }
}

output "node_role_arn" {
  description = "ARN of the IAM role used by the worker nodes."
  value       = aws_iam_role.node_group.arn
}

output "launch_template_ids" {
  description = "Map of launch template IDs created for the node groups."
  value       = { for k, v in aws_launch_template.eks_node_group : k => v.id }
}
