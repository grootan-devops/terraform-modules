output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = module.cluster.cluster_name
}

output "cluster_arn" {
  description = "ARN of the EKS cluster."
  value       = module.cluster.cluster_arn
}

output "cluster_endpoint" {
  description = "Endpoint URL for the Kubernetes API server."
  value       = module.cluster.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data required to communicate with the cluster."
  value       = module.cluster.cluster_certificate_authority_data
}

output "cluster_security_group_id" {
  description = "Security group ID created by AWS EKS for cluster-to-node communication."
  value       = module.cluster.cluster_security_group_id
}

output "cluster_role_arn" {
  description = "IAM role ARN used by the EKS control plane."
  value       = module.cluster.cluster_role_arn
}

output "node_group_arns" {
  description = "Map of node group keys to their resource ARNs."
  value       = try(module.node_group[0].node_group_arns, {})
}

output "node_group_ids" {
  description = "Map of node group keys to their resource IDs."
  value       = try(module.node_group[0].node_group_ids, {})
}

output "node_role_arn" {
  description = "ARN of the IAM role used by the worker nodes."
  value       = try(module.node_group[0].node_role_arn, null)
}
