module "vpc" {
  source = "../../../modules/aws/network/vpc"

  application = var.application
  environment = var.environment
  cidr_block  = "10.30.0.0/16"
  nat         = { mode = "per_az" }

  alarms = { topic_arns = local.alarm_topics }
}

module "images" {
  source = "../../../modules/aws/compute/ecr"

  application = var.application
  environment = var.environment
  name        = "web"
}

module "assets" {
  source = "../../../modules/aws/storage/s3"

  application = var.application
  environment = var.environment
  name        = "assets"
  kms         = { create = true }

  alarms = { topic_arns = local.alarm_topics }
}

module "worker_role" {
  source = "../../../modules/aws/security/iam-role"

  application = var.application
  environment = var.environment
  name        = "worker"
  purpose     = "pod"
  trust = {
    services = ["pods.eks.amazonaws.com"]
    actions  = ["sts:AssumeRole", "sts:TagSession"]
  }
  policy_statements = [{ sid = "WriteAssets", actions = ["s3:PutObject"], resources = ["${module.assets.arn}/*"] }]
}

module "cluster" {
  source = "../../../modules/aws/compute/eks"

  application     = var.application
  environment     = var.environment
  cluster_version = "1.37"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnet_ids
  kms             = { create = true }
  node_groups = {
    general = { instance_types = ["m7g.large"], ami_type = "AL2023_ARM_64_STANDARD", min_size = 2, max_size = 6 }
  }
  access_entries = {
    platform = {
      principal_arn       = "arn:aws:iam::123456789012:role/platform-admin"
      policy_associations = { admin = { policy = "AmazonEKSClusterAdminPolicy" } }
    }
  }
  pod_identities = {
    web = {
      namespace         = "web"
      service_account   = "web"
      policy_statements = [{ sid = "ReadAssets", actions = ["s3:GetObject"], resources = ["${module.assets.arn}/*"] }]
    }
    worker = {
      namespace       = "jobs"
      service_account = "worker"
      role_arn        = module.worker_role.arn
    }
  }

  alarms = { topic_arns = local.alarm_topics }
}
