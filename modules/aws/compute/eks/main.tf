module "cluster" {
  source = "./cluster"

  application            = var.application
  environment            = var.environment
  name                   = var.name
  tags                   = var.tags
  kms_key_arn            = var.kms_key_arn
  cluster_version        = var.cluster_version
  subnet_ids             = var.control_plane_subnet_ids
  security_group_ids     = var.security_group_ids
  endpoint_public_access = var.endpoint_public_access
  public_access_cidrs    = var.public_access_cidrs
}

module "node_group" {
  source = "./node_group"

  count = length(var.node_groups) > 0 ? 1 : 0

  application  = var.application
  environment  = var.environment
  name         = var.name
  tags         = var.tags
  cluster_name = module.cluster.cluster_name
  kms_key_arn  = var.kms_key_arn
  node_groups  = var.node_groups

  depends_on = [module.cluster]
}
