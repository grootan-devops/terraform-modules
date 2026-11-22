output "cluster_name" {
  description = "Cluster name."
  value       = module.cluster.name
}

output "repository_name" {
  description = "Image repository name."
  value       = module.images.name
}

output "assets_bucket" {
  description = "Assets bucket name."
  value       = module.assets.name
}
